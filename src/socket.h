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

void sendAndReceiveExact(Socket, const char* src, size_t srcSize,
	void* dst, size_t dstSize);
#ifdef __cplusplus
extern "C"
#endif
void sendExact(Socket, const char* src, size_t srcSize);

Socket connectNewSocket(const char* address, ushort port) __attribute__ ((warn_unused_result));

typedef void (*SocketTimerCallback)(double t, void* user);

// Causes callback to be called asap after min(t, oldT).
void socketSetTimer(double t, SocketTimerCallback callback, void* user);

// Cancels the timer with the specified callback and user data.
// If no such timer exists, it's a fatal error.
void socketRemoveTimer(SocketTimerCallback callback, void* user);
