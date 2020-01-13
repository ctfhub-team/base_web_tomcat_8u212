FROM openjdk:8u212-jdk-alpine

LABEL Organization="CTFHUB" Author="Virink <virink@outlook.com>"

ENV CATALINA_HOME /usr/local/tomcat
ENV PATH $CATALINA_HOME/bin:$PATH

# let "Tomcat Native" live somewhere isolated
ENV TOMCAT_NATIVE_LIBDIR $CATALINA_HOME/native-jni-lib
ENV LD_LIBRARY_PATH ${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$TOMCAT_NATIVE_LIBDIR

ENV TOMCAT_MAJOR=8 TOMCAT_VERSION=8.5.50 TOMCAT_SHA512=ffca86027d298ba107c7d01c779318c05b61ba48767cc5967ee6ce5a88271bb6ec8eed60708d45453f30eeedddcaedd1a369d6df1b49eea2cd14fa40832cfb90

ENV TOMCAT_TGZ_URL \
	http://mirrors.aliyun.com/apache/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz
	# https://archive.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz

COPY _files /tmp

WORKDIR $CATALINA_HOME

RUN set -eux; \
	\
	mkdir -p "$CATALINA_HOME"; \
	\
	# apk 源
	sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories; \
	apk update; \
	\
	# apk add --no-cache --virtual .fetch-deps \
	# 	gnupg \
	# 	\
	# 	ca-certificates \
	# 	openssl \
	# ; \
	# \
	# GPG
	# export GNUPGHOME="$(mktemp -d)"; \
	# for key in $GPG_KEYS; do \
	# 	gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
	# done; \
	# \
	wget -O tomcat.tar.gz "$TOMCAT_TGZ_URL"; \
	echo "$TOMCAT_SHA512 *tomcat.tar.gz" | sha512sum -c -; \
	\
	# success=; \
	# if wget -O tomcat.tar.gz.asc "$TOMCAT_TGZ_URL.asc"; then \
	# 	success=1; \
	# fi; \
	# [ -n "$success" ]; \
	# \
	# gpg --batch --verify tomcat.tar.gz.asc tomcat.tar.gz; \
	tar -xvf tomcat.tar.gz --strip-components=1; \
	rm bin/*.bat; \
	rm tomcat.tar.gz*; \
	# command -v gpgconf && gpgconf --kill all || :; \
	# rm -rf "$GNUPGHOME"; \
	\
	nativeBuildDir="$(mktemp -d)"; \
	tar -xvf bin/tomcat-native.tar.gz -C "$nativeBuildDir" --strip-components=1; \
	apk add --no-cache --virtual .native-build-deps \
		apr-dev \
		coreutils \
		dpkg-dev dpkg \
		gcc \
		libc-dev \
		make \
		"openjdk${JAVA_VERSION%%[-~bu]*}"="$JAVA_ALPINE_VERSION" \
		openssl-dev \
	; \
	( \
		export CATALINA_HOME="$PWD"; \
		cd "$nativeBuildDir/native"; \
		gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
		./configure \
			--build="$gnuArch" \
			--libdir="$TOMCAT_NATIVE_LIBDIR" \
			--prefix="$CATALINA_HOME" \
			--with-apr="$(which apr-1-config)" \
			--with-java-home="$(docker-java-home)" \
			--with-ssl=yes; \
		make -j "$(nproc)"; \
		make install; \
	); \
	rm -rf "$nativeBuildDir"; \
	rm bin/tomcat-native.tar.gz; \
	\
	runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive "$TOMCAT_NATIVE_LIBDIR" \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
	apk add --virtual .tomcat-native-rundeps $runDeps; \
	# apk del .fetch-deps .native-build-deps; \
	apk del .native-build-deps; \
	\
	apk add --no-cache bash; \
	find ./bin/ -name '*.sh' -exec sed -ri 's|^#!/bin/sh$|#!/usr/bin/env bash|' '{}' +; \
	\
	chmod -R +rX .; \
	chmod 777 logs work; \
	\
	sed -i 's#port="8080"#port="80"#g' $CATALINA_HOME/conf/server.xml; \
	\
	chmod +x /tmp/docker-entrypoint; \
	chmod +x /tmp/flag.sh; \
	mv /tmp/docker-entrypoint /usr/local/bin/docker-entrypoint; \
	mv /tmp/flag.sh /flag.sh; \
	\
	# Verify Tomcat Native is working properly
	nativeLines="$(catalina.sh configtest 2>&1)" \
	&& nativeLines="$(echo "$nativeLines" | grep 'Apache Tomcat Native')" \
	&& nativeLines="$(echo "$nativeLines" | sort -u)" \
	&& if ! echo "$nativeLines" | grep 'INFO: Loaded APR based Apache Tomcat Native library' >&2; then \
		echo >&2 "$nativeLines"; \
		exit 1; \
	fi

EXPOSE 80

CMD ["docker-entrypoint"]