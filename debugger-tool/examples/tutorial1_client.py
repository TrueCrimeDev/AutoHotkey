#!/usr/bin/env python3
"""
Tutorial 1: Basic stepping and variable inspection
Shows how to step through script line-by-line and inspect variables
"""
import socket
import xml.etree.ElementTree as ET
import base64

class DebugClient:
    def __init__(self, port=9000):
        self.port = port
        self.trans_id = 0
        self.sock = None

    def connect(self):
        """Listen for AHK connection"""
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(('localhost', self.port))
        server.listen(1)

        print(f"[*] Listening on localhost:{self.port}...")
        self.sock, addr = server.accept()
        print(f"[+] AHK connected from {addr}")

        # Receive init
        init = self._receive()
        root = self._parse_xml(init)
        print(f"[+] Session: {root.get('session')}")
        print(f"[+] File: {root.get('fileuri')}")

    def _receive(self):
        """Receive DBGp message"""
        # Read length
        length_buf = b''
        while b'\0' not in length_buf:
            length_buf += self.sock.recv(1)
        length = int(length_buf.rstrip(b'\0'))

        # Read data
        data = b''
        while len(data) < length + 1:
            data += self.sock.recv(length + 1 - len(data))

        return data.rstrip(b'\0').decode('utf-8')

    def _send(self, cmd):
        """Send command"""
        self.trans_id += 1
        message = f"{cmd} -i {self.trans_id}\0"
        self.sock.send(message.encode('utf-8'))
        return self.trans_id

    def _parse_xml(self, xml_str):
        """Parse XML response"""
        if xml_str.startswith('<?xml'):
            xml_str = xml_str[xml_str.index('>') + 1:]
        return ET.fromstring(xml_str)

    def _command(self, cmd):
        """Send command and get response"""
        self._send(cmd)
        response = self._receive()
        return self._parse_xml(response)

    def step_into(self):
        """Step into next line"""
        resp = self._command("step_into")
        status = resp.get('status')
        print(f"[→] step_into: status={status}")
        return resp

    def get_stack(self):
        """Get current stack"""
        resp = self._command("stack_get")
        frames = []
        for stack in resp.findall('stack'):
            frames.append({
                'level': int(stack.get('level')),
                'where': stack.get('where', ''),
                'filename': stack.get('filename', ''),
                'lineno': int(stack.get('lineno', 0))
            })
        return frames

    def get_variable(self, name):
        """Get variable value"""
        resp = self._command(f"property_get -n {name}")
        prop = resp.find('property')
        if prop is not None:
            value = prop.text or ''
            if prop.get('encoding') == 'base64':
                value = base64.b64decode(value).decode('utf-8')
            return value
        return None

    def get_all_variables(self):
        """Get all local variables"""
        resp = self._command("context_get")
        variables = {}
        for prop in resp.findall('.//property'):
            name = prop.get('name')
            value = prop.text or ''
            if prop.get('encoding') == 'base64':
                value = base64.b64decode(value).decode('utf-8')
            variables[name] = value
        return variables

# Main script
def main():
    print("="*60)
    print("TUTORIAL 1: Basic Stepping and Variable Inspection")
    print("="*60)
    print()
    print("This tutorial demonstrates:")
    print("  - Connecting to AHK debugger")
    print("  - Stepping through script line-by-line")
    print("  - Inspecting variables at each step")
    print()
    print("Start AHK with: AutoHotkey.exe /Debug tutorial1.ahk")
    print("="*60)
    print()

    client = DebugClient()
    client.connect()

    print("\n" + "="*60)
    print("Stepping through script...")
    print("="*60)

    # Step through first several lines
    for step_num in range(1, 10):
        print(f"\n--- Step {step_num} ---")

        # Step into next line
        resp = client.step_into()

        if resp.get('status') == 'stopped':
            print("Script completed!")
            break

        # Get current location
        stack = client.get_stack()
        if stack:
            frame = stack[0]
            print(f"Location: Line {frame['lineno']}")

        # Get all variables
        variables = client.get_all_variables()
        if variables:
            print("Variables:")
            for name, value in variables.items():
                print(f"  {name} = {value}")

    print("\n" + "="*60)
    print("Tutorial complete! Letting script finish...")
    print("="*60)

    # Let script finish
    client._command("run")

if __name__ == '__main__':
    main()
