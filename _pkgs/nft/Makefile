$(call configure-package,\
	https://netfilter.org/projects/nftables/files/nftables-1.0.7.tar.xz,\
	c12ac941fff9adaedf17367d5ce213789b98a0d314277bc22b3d71e10891f412,\
	--disable-debug --disable-man-doc --disable-python --with-mini-gmp --without-cli --without-xtables --without-json --without-python-bin\
	LIBMNL_CFLAGS='-I$${libmnl}/include' LIBMNL_LIBS='-L$${libmnl}/src/.libs -lmnl'\
	LIBNFTNL_CFLAGS='-I$${libnftnl}/include' LIBNFTNL_LIBS='-L$${libnftnl}/src/.libs -lnftnl'\
)
