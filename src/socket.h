
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

void receiveExact(Socket, void* dst, size_t dstSize);
void sendAndReceiveExact(Socket, const char* src, size_t srcSize,
	void* dst, size_t dstSize);
#ifdef __cplusplus
extern "C"
#endif
void sendExact(Socket, const char* src, size_t srcSize);
