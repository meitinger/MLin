$(call configure-package,\
	https://netfilter.org/projects/conntrack-tools/files/conntrack-tools-1.4.7.tar.bz2,\
	099debcf57e81690ced57f516b493588a73518f48c14d656f823b29b4fc24b5d,\
	--disable-cthelper --disable-cttimeout --disable-systemd\
	LIBTIRPC_CFLAGS='-I$${libtirpc}/include' LIBTIRPC_LIBS='-L$${libtirpc}/src/.libs -ltirpc'\
	LIBNFNETLINK_CFLAGS='-I$${libnfnetlink}/include' LIBNFNETLINK_LIBS='-L$${libnfnetlink}/src/.libs -lnfnetlink'\
	LIBMNL_CFLAGS='-I$${libmnl}/include' LIBMNL_LIBS='-L$${libmnl}/src/.libs -lmnl'\
	LIBNETFILTER_CONNTRACK_CFLAGS='-I$${libnetfilter_conntrack}/include' LIBNETFILTER_CONNTRACK_LIBS='-L$${libnetfilter_conntrack}/src/.libs -lnetfilter_conntrack'\
)
