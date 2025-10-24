#!/usr/bin/env python3
"""
Simple AutoHotkey v2 Debugger Client
Demonstrates basic connection and execution control
"""
import socket
import xml.etree.ElementTree as ET

def receive_message(sock):
    """Receive DBGp message: [length]\0[XML]\0"""
    # Read length
    length_buf = b''
    while b'\0' not in length_buf:
        length_buf += sock.recv(1)

    length = int(length_buf.rstrip(b'\0'))

    # Read data
    data = b''
    while len(data) < length + 1:
        chunk = sock.recv(length + 1 - len(data))
        if not chunk:
            raise ConnectionError("Socket closed")
        data += chunk

    return data.rstrip(b'\0').decode('utf-8')

def send_command(sock, cmd, trans_id):
    """Send DBGp command"""
    message = f"{cmd} -i {trans_id}\0"
    sock.send(message.encode('utf-8'))

# Main
print("[*] Simple AutoHotkey v2 Debugger Client")
print("[*] Listening on localhost:9000...")

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('localhost', 9000))
server.listen(1)

print("[*] Waiting for AutoHotkey to connect...")
print("    Start AHK with: AutoHotkey.exe /Debug script.ahk")
print()

client, addr = server.accept()
print(f"[+] Connected from {addr}")

# Receive init message
init = receive_message(client)
print(f"\n[+] Init message received:")
print(init[:300] + "...")

# Send run command
print("\n[*] Sending 'run' command to continue execution...")
send_command(client, "run", 1)
response = receive_message(client)
print(f"[+] Response: {response[:200]}")

print("\n[*] Script is running. It will send status updates as it executes.")

# Wait for completion
try:
    while True:
        msg = receive_message(client)
        print(f"\n[+] Received: {msg[:200]}")
        if 'status="stopped"' in msg:
            print("\n[+] Script execution completed!")
            break
except Exception as e:
    print(f"\n[!] Connection closed: {e}")

client.close()
server.close()
print("\n[*] Debugger session ended.")
