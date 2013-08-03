#include <stdint.h>

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

typedef uint16_t ushort;
typedef uint8_t byte;

Socket connectNewSocket(const char* address, ushort port) __attribute__ ((warn_unused_result));
