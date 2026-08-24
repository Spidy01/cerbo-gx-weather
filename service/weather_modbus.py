#!/usr/bin/env python3
import json
import logging
import os
import socket
import struct
import sys
import time
from pathlib import Path

from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

VERSION = "3.0.0"
BASE = Path(__file__).resolve().parent
CONFIG_FILE = BASE / "config.json"

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("weather-modbus")

for candidate in (
    "/opt/victronenergy/dbus-systemcalc-py/ext/velib_python",
    "/opt/victronenergy/velib_python",
):
    if os.path.exists(os.path.join(candidate, "vedbus.py")):
        sys.path.insert(0, candidate)
        break

from vedbus import VeDbusService


class ModbusTCP:
    def __init__(self, host, port=502, unit_id=1, timeout=2.0):
        self.host = host
        self.port = int(port)
        self.unit_id = int(unit_id)
        self.timeout = float(timeout)
        self.transaction_id = 0

    @staticmethod
    def _recv_exact(sock, count):
        data = b""
        while len(data) < count:
            chunk = sock.recv(count - len(data))
            if not chunk:
                raise IOError("Modbus TCP connection closed")
            data += chunk
        return data

    def _request(self, pdu):
        self.transaction_id = (self.transaction_id + 1) & 0xFFFF
        mbap = struct.pack(">HHHB", self.transaction_id, 0, len(pdu) + 1, self.unit_id)
        with socket.create_connection((self.host, self.port), self.timeout) as sock:
            sock.settimeout(self.timeout)
            sock.sendall(mbap + pdu)
            header = self._recv_exact(sock, 7)
            transaction_id, protocol_id, length, unit_id = struct.unpack(">HHHB", header)
            if transaction_id != self.transaction_id or protocol_id != 0:
                raise IOError("Invalid Modbus TCP response header")
            payload = self._recv_exact(sock, length - 1)

        if not payload:
            raise IOError("Empty Modbus TCP response")
        if payload[0] & 0x80:
            code = payload[1] if len(payload) > 1 else -1
            raise IOError("Modbus exception %s" % code)
        return payload

    def read_holding_registers(self, address0, count):
        if count < 1 or count > 125:
            raise ValueError("FC03 register count must be 1..125")
        payload = self._request(struct.pack(">BHH", 3, int(address0), int(count)))
        if payload[0] != 3:
            raise IOError("Unexpected Modbus function %s" % payload[0])
        byte_count = payload[1]
        if byte_count != count * 2:
            raise IOError("Unexpected Modbus byte count %s" % byte_count)
        return [
            struct.unpack(">H", payload[2 + i * 2:4 + i * 2])[0]
            for i in range(count)
        ]


def protocol_address(register, addressing):
    register = int(register)
    if addressing == "4xxxx":
        if register < 40001:
            raise ValueError("4xxxx register must be >= 40001")
        return register - 40001
    if addressing == "one_based":
        return register - 1
    if addressing == "zero_based":
        return register
    raise ValueError("Unsupported addressing mode: %s" % addressing)


def decode_float32(words, float_order):
    if len(words) != 2:
        raise ValueError("float32 requires two 16-bit registers")
    order = float_order.upper()
    if order == "CDAB":
        words = [words[1], words[0]]
    elif order != "ABCD":
        raise ValueError("float_order must be ABCD or CDAB")
    return struct.unpack(">f", struct.pack(">HH", words[0], words[1]))[0]


class WeatherService:
    def __init__(self, config):
        self.config = config
        modbus = config["modbus"]
        if not modbus.get("host") or modbus["host"] == "CHANGE_ME":
            raise SystemExit("Set modbus.host in /data/weather-modbus/config.json")

        self.addressing = modbus.get("addressing", "4xxxx")
        self.float_order = modbus.get("float_order", "ABCD")
        self.poll_ms = max(500, int(float(modbus.get("poll_seconds", 2.0)) * 1000))
        self.client = ModbusTCP(
            modbus["host"],
            modbus.get("port", 502),
            modbus.get("unit_id", 1),
            modbus.get("timeout_seconds", 2.0),
        )

        dbus_cfg = config["dbus"]
        self.dbus = VeDbusService(dbus_cfg["service_name"], register=False)
        self.dbus.add_mandatory_paths(
            processname=__file__,
            processversion=VERSION,
            connection=dbus_cfg.get("connection", "Modbus TCP"),
            deviceinstance=int(dbus_cfg.get("device_instance", 40)),
            productid=0,
            productname=dbus_cfg.get("product_name", "CR6 Weather Station"),
            firmwareversion=VERSION,
            hardwareversion="Campbell CR6 / ClimaVue 50 G2",
            connected=0,
        )
        self.dbus.add_path("/Status", "Starting")
        self.dbus.add_path("/LastUpdate", "")
        self.dbus.add_path("/UpdateAge", 0)
        self.dbus.add_path("/PollOk", 0)
        self.dbus.add_path("/Error", "")
        self.dbus.add_path("/RegisterMapVersion", "CR6-weather-v1")

        for item in config["registers"]:
            self.dbus.add_path(item["path"], None)

        self.dbus.register()
        self.last_ok = None

        spans = []
        for item in config["registers"]:
            start = protocol_address(item["register"], self.addressing)
            width = 2 if item.get("type", "float32") == "float32" else 1
            spans.append((start, start + width - 1))
        self.start_address = min(start for start, _ in spans)
        self.end_address = max(end for _, end in spans)
        self.read_count = self.end_address - self.start_address + 1
        if self.read_count > 125:
            raise ValueError("Configured register span exceeds one FC03 request")

        log.info(
            "Reading CR6 %s:%s unit %s, FC03 protocol addresses %s..%s (%s registers)",
            modbus["host"], modbus.get("port", 502), modbus.get("unit_id", 1),
            self.start_address, self.end_address, self.read_count,
        )

    def _decode(self, raw_registers, item):
        address = protocol_address(item["register"], self.addressing)
        offset = address - self.start_address
        data_type = item.get("type", "float32")
        if data_type == "float32":
            value = decode_float32(raw_registers[offset:offset + 2], self.float_order)
        elif data_type == "uint16":
            value = raw_registers[offset]
        elif data_type == "int16":
            value = raw_registers[offset]
            if value >= 32768:
                value -= 65536
        else:
            raise ValueError("Unsupported data type: %s" % data_type)

        value *= float(item.get("multiplier", 1.0))
        return round(value, int(item.get("decimals", 2)))

    def poll(self):
        try:
            raw = self.client.read_holding_registers(self.start_address, self.read_count)
            for item in self.config["registers"]:
                self.dbus[item["path"]] = self._decode(raw, item)

            self.last_ok = time.time()
            self.dbus["/Connected"] = 1
            self.dbus["/Status"] = "Online"
            self.dbus["/PollOk"] = 1
            self.dbus["/Error"] = ""
            self.dbus["/LastUpdate"] = time.strftime("%Y-%m-%d %H:%M:%S")
        except Exception as exc:
            self.dbus["/Connected"] = 0
            self.dbus["/Status"] = "Offline"
            self.dbus["/PollOk"] = 0
            self.dbus["/Error"] = str(exc)[:200]
            log.warning("Poll failed: %s", exc)

        self.dbus["/UpdateAge"] = 0 if self.last_ok is None else int(time.time() - self.last_ok)
        return True


def main():
    config = json.loads(CONFIG_FILE.read_text())
    DBusGMainLoop(set_as_default=True)
    service = WeatherService(config)
    service.poll()
    GLib.timeout_add(service.poll_ms, service.poll)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
