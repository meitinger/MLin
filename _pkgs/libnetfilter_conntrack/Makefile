$(call configure-package,\
	https://netfilter.org/projects/libnetfilter_conntrack/files/libnetfilter_conntrack-1.0.9.tar.bz2,\
	67bd9df49fe34e8b82144f6dfb93b320f384a8ea59727e92ff8d18b5f4b579a8,\
	LIBNFNETLINK_CFLAGS='-I$${libnfnetlink}/include' LIBNFNETLINK_LIBS='-L$${libnfnetlink}/src/.libs -lnfnetlink'\
	LIBMNL_CFLAGS='-I$${libmnl}/include' LIBMNL_LIBS='-L$${libmnl}/src/.libs -lmnl'\
)
