/*
DebugTransport.h - Abstract transport layer for the debugger engine.

Provides SocketTransport (TCP, original behavior) and StdioTransport
(stdin/stdout pipes for tool integration).

Usage: /Debug or /Debug=host:port  -> SocketTransport
       /Debug=stdio                -> StdioTransport
*/

#pragma once

#ifdef CONFIG_DEBUGGER

#include <winsock2.h>
#include <io.h>
#include <fcntl.h>

class DebugTransport
{
public:
	virtual ~DebugTransport() {}

	// Establish the connection. For sockets, this does TCP connect.
	// For stdio, this is a no-op (pipes are already open).
	// Returns DEBUGGER_E_OK on success.
	virtual int Connect(const char *aAddress, const char *aPort) = 0;

	// Close the connection.
	virtual void Disconnect() = 0;

	// Send data to the debugger client.
	// Returns 0 on success, non-zero on error.
	virtual int Send(const char *aData, size_t aSize) = 0;

	// Receive data from the debugger client.
	// Sets aBytesRead to the number of bytes read. Returns 0 on success.
	virtual int Recv(char *aBuffer, size_t aBufferSize, int &aBytesRead) = 0;

	// Check if there is pending data available to read without blocking.
	virtual bool HasPendingData() = 0;

	// Check if the transport is currently connected.
	virtual bool IsConnected() = 0;

	// Called when entering the synchronous command processing loop.
	// Socket transport disables async notifications here.
	virtual void EnterSyncMode(HWND aWnd) {}

	// Called when exiting the synchronous command processing loop.
	// Socket transport re-enables async notifications here.
	virtual void ExitSyncMode(HWND aWnd) {}
};


// SocketTransport - TCP transport (original debugger behavior)
class SocketTransport : public DebugTransport
{
	SOCKET mSocket = INVALID_SOCKET;
	bool mWsaInitialized = false;

public:
	int Connect(const char *aAddress, const char *aPort) override;
	void Disconnect() override;
	int Send(const char *aData, size_t aSize) override;
	int Recv(char *aBuffer, size_t aBufferSize, int &aBytesRead) override;
	bool HasPendingData() override;
	bool IsConnected() override { return mSocket != INVALID_SOCKET; }
	void EnterSyncMode(HWND aWnd) override;
	void ExitSyncMode(HWND aWnd) override;
};


// StdioTransport - stdin/stdout transport for tool integration
class StdioTransport : public DebugTransport
{
	bool mConnected = false;
	HANDLE mInput = INVALID_HANDLE_VALUE;

public:
	int Connect(const char *aAddress, const char *aPort) override;
	void Disconnect() override;
	int Send(const char *aData, size_t aSize) override;
	int Recv(char *aBuffer, size_t aBufferSize, int &aBytesRead) override;
	bool HasPendingData() override;
	bool IsConnected() override { return mConnected; }
};


#endif // CONFIG_DEBUGGER
