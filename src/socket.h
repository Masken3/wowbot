#ifndef SOCKET_H
#define SOCKET_H

#include <stdint.h>
#include "types.h"

#if defined(WIN32) || defined(_WIN32_WCE)
//#include <windows.h>
#include <winsock2.h>
typedef SOCKET Socket;
#define SOCKET_ERRNO WSAGetLastError()
typedef int socklen_t;

#else	//GNU libc

#include <sys/socket.h>
#include <errno.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/tcp.h>
typedef int Socket;
#define INVALID_SOCKET (-1)
#define SOCKET_ERROR (-1)
#define SOCKET_ERRNO errno
#define closesocket ::close
#endif

#define ST(func)

// returns the number of bytes received.
// 0 on remote disconnect, <0 on error.
int receiveExact(Socket, void* dst, size_t dstSize) __attribute__ ((warn_unused_result));

// returns > 0 on success, 0 on timeout. exits on error.
int receiveExactWithTimeout(Socket sock, void* dst, size_t dstSize, uint seconds);

void sendAndReceiveExact(Socket, const char* src, size_t srcSize,
	void* dst, size_t dstSize);
#ifdef __cplusplus
extern "C"
#endif
void sendExact(Socket, const char* src, size_t srcSize);

Socket connectNewSocket(const char* address, ushort port) __attribute__ ((warn_unused_result));


// structures and function for handling multiple simultaneous sockets.

struct SocketControl;

// return 0 to continue the loop, non-zero to break it.
// runSocketControl() returns the value this function returned.
// it's your responsibility to close any sockets left open.
typedef int (*SocketTimerCallback)(double t, struct SocketControl*);
typedef int (*SocketDataCallback)(struct SocketControl*, int result);

// dataCallback will be called when dstSize bytes have been received and written to dst.
typedef struct SocketControl {
	Socket sock;
	void* dst;
	uint dstSize;
	SocketDataCallback dataCallback;
	SocketTimerCallback timerCallback;
	void* user;
	double timerTime;

	// set and controlled by runSocketControl(). do not modify.
	uint dstPos;
} SocketControl;

// count is the length of the array pointed to by p.
int runSocketControl(SocketControl* p, int count);

#endif	//SOCKET_H
