/* iOS 6 adjustments on top of mbedTLS's default mbedtls_config.h.
 * clock_gettime() only exists on iOS 10+, so mbedtls_ms_time() comes from mbedtls_ios6_alt.c (mach_absolute_time). */
#define MBEDTLS_PLATFORM_MS_TIME_ALT

/* Thread safety: the app runs TLS connections on several threads at once (API calls, cover downloads). Without this the
 * PSA key store used by TLS 1.3 and the RNG are shared without locks, and parallel handshakes corrupt each other's memory. */
#define MBEDTLS_THREADING_C
#define MBEDTLS_THREADING_PTHREAD
