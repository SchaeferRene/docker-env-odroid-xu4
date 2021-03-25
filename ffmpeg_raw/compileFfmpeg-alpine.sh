#! /bin/sh

#####################
### Configuration ###
#####################
## Paths
SCRIPT_NAME=$(basename $0)
export PREFIX=/opt/ffmpeg
export OWN_PKG_CONFIG_PATH="$PREFIX/share/pkgconfig:$PREFIX/lib64/pkgconfig:$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH="$OWN_PKG_CONFIG_PATH:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/lib64/pkgconfig:/lib/pkgconfig"
export LD_LIBRARY_PATH="$PREFIX/lib64:$PREFIX/lib:/usr/local/lib64:/usr/local/lib:/usr/lib64:/usr/lib:/lib64:/lib"
export MAKEFLAGS=-j2
export CFLAGS="-fPIC"
export CXXFLAGS="-fPIC"
export PATH="$PREFIX/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LDFLAGS=""

mkdir -p "$PREFIX"

# some text color constants
Color_Off='\033[0m'	# Text Reset
On_IRed='\033[0;101m'	# Red Inverse

## script vars
FFMPEG_FEATURES=""
FFMPEG_EXTRA_LIBS=""
THEORA_FLAGS=""

# Build config
export BUILDING_DAVS2=disabled
export BUILDING_XAVS2=disabled
export BUILDING_ZIMG=disabled

echo -e "${On_IRed}--- Configuration:${Color_Off}"
env | grep BUILDING_ | sort
echo

########################
### Common functions ###
########################
addFeature() {
	[ $(echo "$FFMPEG_FEATURES" | grep -q -- "$1"; echo $?) -eq 0 ] \
		|| FFMPEG_FEATURES="$FFMPEG_FEATURES $1"
}

addExtraLib() {
	[ $(echo "$FFMPEG_EXTRA_LIBS" | grep -q -- "$1"; echo $?) -eq 0 ] \
		|| FFMPEG_EXTRA_LIBS="$FFMPEG_EXTRA_LIBS $1"
}

installFfmpegToolingDependencies() {
	echo -e "${On_IRed}--- Installing Tooling Dependencies${Color_Off}"
	
	# below dependencies are required to build core ffmpeg according to generic compilation guide
	apk add --no-cache --update \
		autoconf \
		automake \
		build-base \
		cmake \
		curl \
		git \
		libtool \
		pkgconfig \
		tar \
		texinfo \
		wget \
		yasm
	RESULT=$?
	echo

	#echo "--- Installing ffmpeg build Dependencies"
	#apk add --no-cache \
	#	libva-dev libvdpau-dev \
	#	sdl2-dev sdl2-static sdl2_ttf-dev \
	#
	#echo
	return $RESULT
}

sanityCheck() {
	echo

	if [[ $RESULT -eq 0 ]]; then
		echo "--- Compilation succeeded"
		for PRG in ffmpeg ffprobe ffplay
		do
			PRG="$PREFIX/bin/$PRG"
			if [[ -f "$PRG" ]]; then
				echo
				echo "${PRG} -version" && ${PRG} -version
				echo -n "${PRG} dependencies:" && echo $(ldd "$PRG" | wc -l)
				echo
			fi
		done
	else
		echo "--- Build failed with exit status" $RESULT
		[ -f ffbuild/config.log ] && tail -10 ffbuild/config.log
	fi
}

hasBeenInstalled() {
	if [ -z "$2" ]; then
		PCP=$PKG_CONFIG_PATH
	else
		PCP=$OWN_PKG_CONFIG_PATH
	fi
	
	echo "--- Checking $1 in $PCP"

	CHECK=$(PKG_CONFIG_PATH="$PCP" pkg-config --exists --no-cache --env-only --shared --print-errors $1; echo $?)
	
	[ $CHECK -eq 0 ] && echo "... found" || echo "... not found"
	echo
}

provide () {
	echo -e $On_IRed
	[ $RESULT -ne 0 ] && echo -e "!!! Skipping $1 due to previous error$Color_Off" && return $RESULT

	BUILD_VAR=BUILDING_$(echo "$1" | tr [:lower:] [:upper:])
	eval val="\$$BUILD_VAR"
	METHOD=$(echo "$val" | grep -E "install|compile|disabled")
	
	if [ "$METHOD" == "disabled" ]; then
		echo -e "!!! Skipping disabled $1$Color_Off"
		return 0
	elif [ -n "$METHOD" ]; then
		fn_exists "$METHOD$1"
		RESULT=$?
		if [ $RESULT -ne 0 ]; then
			echo "missing functions install$1 or compile$1"
			return $RESULT
		elif [ "$METHOD" == "compile" ]; then
			echo -e "--- Compiling $1$Color_Off"
			eval "$METHOD$1"
		else
			echo -e "--- Installing $1$Color_Off"
			eval "$METHOD$1"
		fi
	else
		fn_exists "install$1"
		RESULT=$?
		if [ $RESULT -eq 0 ]; then
			echo -e "--- Installing $1$Color_Off"
			eval "install$1"
		else
			fn_exists "compile$1"
			RESULT=$?
			if [ $RESULT -ne 0 ]; then 
				echo "!!! missing functions install$1 or compile$1"
			else
				echo -e "--- Compiling $1$Color_Off"
				eval "compile$1"
			fi
		fi
	fi

	TMP=$?
	[ $RESULT -eq 0 ] && RESULT=$TMP
	
	[ $RESULT -eq 0 ] \
		&& echo -e "${On_IRed}... done providing $1$Color_Off" \
		|| echo -e "${On_IRed}!!! failed to provide $1 with RC $RESULT$Color_Off" 
}

fn_exists () {
	type $1 >/dev/null 2>&1;
}

####################
### Dependencies ###
####################

################
### Features ###
################

## Supplementary ##
compileAribb24() {
        hasBeenInstalled aribb24 true

        [ $CHECK -eq 0 ] \
        && echo "--- Skipping already built aribb24" \
        || {
		apk add --no-cache libpng-dev

                DIR=/tmp/aribb24
                mkdir -p "$DIR"
                cd "$DIR"

		RELEASE=$( curl --silent https://github.com/nkoriyama/aribb24/releases/latest | sed -E 's/.*"([^"]+)".*/\1/')
		RELEASE=$(basename $RELEASE)

		curl -sLO https://github.com/nkoriyama/aribb24/archive/${RELEASE}.tar.gz \
		&& tar -xz --strip-components=1 -f ${RELEASE}.tar.gz \
		&& autoreconf -fiv \
                && ./configure \
			CFLAGS="-I${PREFIX}/include -fPIC" \
                        --prefix="$PREFIX" \
                        --enable-shared=yes \
                        --enable-static=no \
                && make \
                && make install \
                && cd \
                && rm -rf "$DIR"
        }

        addFeature --enable-libaribb24
}

installFreetype() {
	apk add --no-cache freetype-dev \
	&& addFeature --enable-libfreetype
}

installFribidi() {
	apk add --no-cache fribidi-dev \
	&& addFeature --enable-libfribidi
}

installFontConfig() {
	apk add --no-cache fontconfig-dev \
	&& addFeature --enable-fontconfig
}

installLibAss () {
	apk add --no-cache libass-dev \
        && addFeature --enable-libass
}

installLibBluray() {
	apk add --no-cache libbluray-dev \
	&& addFeature --enable-libbluray
}

installLibXcb() {
	apk add --no-cache libxcb-dev \
	&& addFeature --enable-libxcb \
	&& addFeature --enable-libxcb-shm \
	&& addFeature --enable-libxcb-xfixes \
	&& addFeature --enable-libxcb-shape
}

installOpenSsl() {
	apk add --no-cache openssl-dev \
	&& addFeature --enable-openssl
}

installSrt() {
	apk add --no-cache libsrt-dev \
	&& addFeature --enable-libsrt
}

installVidStab() {
	apk add --no-cache vidstab-dev \
	&& addFeature --enable-libvidstab
}

installXml2() {
	apk add --no-cache libxml2-dev \
	&& addFeature --enable-libxml2
}

installZeroMq() {
	apk add --no-cache zeromq-dev \
	&& addFeature --enable-libzmq
}

compileZimg() {
	hasBeenInstalled zimg true

	[ $CHECK -eq 0 ] \
	&& echo "--- Skipping already built zimg" \
	|| {
		DIR=/tmp/zimg
		mkdir -p "$DIR"
		cd "$DIR"

		git clone --depth 1 https://github.com/sekrit-twc/zimg.git
		cd zimg
    	
		./autogen.sh
		./configure \
			--prefix="$PREFIX" \
			--enable-shared=yes \
			--enable-static=no

		make \
		&& make install \
		&& cd \
		&& rm -rf "$DIR"
	}

	addFeature --enable-libzimg
}

## Imaging ##
installOpenJpeg() {
        apk add --no-cache openjpeg-dev \
        && addFeature --enable-libopenjpeg
}

installWebp() {
        apk add --no-cache libwebp-dev \
        && addFeature --enable-libwebp
}

## Audio ##
installFdkAac() {
	apk add --no-cache fdk-aac-dev \
        && addFeature --enable-libfdk-aac
}

installMp3Lame() {
        apk add --no-cache lame-dev \
        && addFeature --enable-libmp3lame
}

installOpus() {
	apk add --no-cache opus-dev \
	&& addFeature --enable-libopus
}

compileOpenCoreAMR() {
	hasBeenInstalled opencore-amrnb true

        [ $CHECK -eq 0 ] \
        && echo "--- Skipping already built OpenCORE AMR" \
        || {
                DIR=/tmp/opencore-amr
                mkdir "$DIR"
                cd "$DIR"

		git clone --depth 1 https://git.code.sf.net/p/opencore-amr/code opencore-amr
		cd opencore-amr

		autoreconf -fiv \
                && ./configure \
			--prefix="$PREFIX" \
			--enable-shared=yes \
			--enable-static=no \
                && make \
		&& make install \
                && cd \
		&& rm -rf "$DIR"

		RESULT=$?
        }

        addFeature --enable-libopencore-amrnb
        addFeature --enable-libopencore-amrwb
}

installSoxr() {
	apk add --no-cache soxr-dev \
	&& addFeature --enable-libsoxr
}

installSpeex() {
	apk add --no-cache speex-dev \
	&& addFeature --enable-libspeex
}

installTheora() {
	apk add --no-cache libtheora-dev \
	&& addFeature --enable-libtheora
}

installVorbis() {
	apk add --no-cache libvorbis-dev \
	&& addFeature --enable-libvorbis
}

## Video ##
installAom() {
        apk add --no-cache aom-dev \
        && addFeature --enable-libaom
}

installDav1d() {
        apk add --no-cache dav1d-dev \
        && addFeature --enable-libdav1d
}

compileDavs2() {
	[ -n "$BUILDING_DAVS2" ] && return
	hasBeenInstalled davs2 true

	[ $CHECK -eq 0 ] \
	&& echo "--- Skipping already built davs2" \
	|| {
		apk add --no-cache nasm

		DIR=/tmp/davs2
		mkdir -p "$DIR"
		cd "$DIR"

		wget https://github.com/pkuvcl/davs2/archive/master.zip -O davs2.zip
		unzip davs2.zip
		cd davs2-master/build/linux/

		./configure \
			--prefix="$PREFIX" \
			--enable-pic \
			--disable-cli \
		&& make \
		&& make install \
		&& cd \
		&& rm -rf "$DIR"

		RESULT=$?
	}

	addFeature --enable-libdavs2
}

compileKvazaar() {
	hasBeenInstalled kvazaar true

	[ $CHECK -eq 0 ] \
	&& echo "--- Skipping already built Kvazaar" \
	|| {
		DIR=/tmp/kvazaar
		mkdir -p "$DIR"
		cd "$DIR"

		git clone --depth 1 https://github.com/ultravideo/kvazaar.git
		cd kvazaar
		
		./autogen.sh
		./configure \
			--prefix="$PREFIX" \
			--enable-shared=yes \
			--enable-static=no \
		&& make \
		&& make install \
		&& cd \
		&& rm -rf "$DIR"

		RESULT=$?
	}

	addFeature --enable-libkvazaar
}

# compile VP8/VP9
installVpx() {
	apk add --no-cache libvpx-dev \
        && addFeature --enable-libvpx
}

installX264() {
        apk add --no-cache x264-dev \
        && addFeature --enable-libx264
}

installX265() {
        apk add --no-cache x265-dev \
        && addFeature --enable-libx265
}

compileX265() {			# TODO: compile as multi-lib
	hasBeenInstalled x265 true

	[ $CHECK -eq 0 ] \
	&& echo "--- Skipping already built x265" \
	|| {
		DIR=/tmp/x265
		mkdir -p "$DIR"
		cd "$DIR"

		git clone https://github.com/videolan/x265.git
		cd x265/build/linux/

		# TODO: 10bit / 12bit 

		# do 8bit build
		mkdir 8bit && cd 8bit
		cmake -G "Unix Makefiles" \
			-DCMAKE_INSTALL_PREFIX="$PREFIX" \
			-DENABLE_SHARED:bool=ON \
			-DENABLE_AGGRESSIVE_CHECKS=ON \
			-DENABLE_PIC=ON \
			-DENABLE_LIBNUMA=OFF \
			-DENABLE_CLI=OFF \
			../../../source \
		&& make
		RESULT=$?

		cd ..
	
		[ $RESULT -eq 0 ] \
		&& make -C 8bit install \
		&& cd \
		&& rm-rf "$DIR"

		RESULT=$?
	}

	addFeature --enable-libx265
}

compileXavs2() {
	[ -n "$BUILDING_XAVS2" ] && return
	hasBeenInstalled xavs2 true

	[ $CHECK -eq 0 ] \
	&& echo "--- Skipping already built xavs2" \
	|| {
		apk add --no-cache nasm

		DIR=/tmp/xavs2
		mkdir -p "$DIR"
		cd "$DIR"

		wget https://github.com/pkuvcl/xavs2/archive/master.zip -O xavs2.zip
		unzip xavs2.zip
		cd xavs2-master/build/linux/

		./configure \
			--prefix="$PREFIX" \
			--enable-pic \
			--enable-shared \
			--disable-cli \
		&& make \
		&& make install \
		&& cd \
		&& rm -rf "$DIR"

		RESULT=$?
	}

	addFeature --enable-libxavs2
}

installXvid() {
	apk add --no-cache xvidcore-dev \
	&& addFeature --enable-libxvid
}

##############
### FFMPEG ###
##############
compileFfmpeg() {
	FFMPEG_OPTIONS="--enable-shared --disable-static --enable-pic --enable-avresample"
	FFMPEG_OPTIONS="$FFMPEG_OPTIONS --disable-debug --disable-doc --disable-ffplay"
	FFMPEG_OPTIONS="$FFMPEG_OPTIONS --enable-gpl --enable-nonfree --enable-version3"
	FFMPEG_OPTIONS="$FFMPEG_OPTIONS --enable-postproc"
	FFMPEG_OPTIONS="$FFMPEG_OPTIONS $FFMPEG_FEATURES"

	echo "--- Compiling ffmpeg with features $FFMPEG_OPTIONS"

	#apk add zlib-dev

	DIR=/tmp/ffmpeg
	if [ -d "$DIR" ]; then
	    rm -rf "$DIR"
	fi
	mkdir -p "$DIR"
	cd "$DIR"

	wget -O ffmpeg-snapshot.tar.bz2 https://ffmpeg.org/releases/ffmpeg-snapshot.tar.bz2
	tar xjf ffmpeg-snapshot.tar.bz2
	cd ffmpeg/

	./configure \
		--env=PKG_CONFIG_PATH="$PKG_CONFIG_PATH" \
		--prefix="$PREFIX" \
		--extra-cflags="-I${PREFIX}/include" \
		--extra-ldflags="-L${PREFIX}/lib" \
		--toolchain=hardened \
		--extra-libs="$FFMPEG_EXTRA_LIBS" \
		$FFMPEG_OPTIONS

	RESULT=$?

	[ $RESULT -eq 0 ] \
	&& make \
	&& make install \
	&& make tools/qt-faststart \
	&& cp tools/qt-faststart ${PREFIX}/bin/

	RESULT=$?

	if [ $RESULT -eq 0 -a $(echo "$FFMPEG_FEATURES" | grep -q -- ""--enable-libzmq; echo $?) -eq 0 ]; then
		make tools/zmqsend \
		&& cp tools/zmqsend ${PREFIX}/bin/

		RESULT=$?
	fi

	[ $RESULT -eq 0 ] \
	&& cd \
	&& rm -rf "$DIR"
}

#############################################
### Comment out what you don't need below ###
#############################################
# note: c=compile, i=install, d=disable
compileSupportingLibs() {	# armv7
	provide Xml2		# i
	provide Freetype	# ic
	provide FontConfig	# c
	provide Fribidi		# i

	provide Aribb24		# c
	provide LibAss		# ic
	provide LibBluray	# i
	provide LibXcb		# i
	provide OpenSsl		# i
	provide Srt		# i
	provide VidStab		# ic
	provide ZeroMq		# i
	provide Zimg		# d*
	: # NOOP

	# *	fails due to missing 'asm/hwcap.h'
}

compileImageLibs() {		# armv7
	provide OpenJpeg	# ic
	provide Webp		# ic
	: # NOOP
}

compileAudioCodecs() {		# armv7
	provide FdkAac		# ic
	provide Mp3Lame		# ic
	provide OpenCoreAMR	# c
	provide Opus		# ic
	provide Soxr		# i
	provide Speex		# ic
	provide Theora		# ic
	provide Vorbis		# ic
	: # NOOP
}

compileVideoCodecs() {		# armv7
	provide Aom		# ic
	provide Dav1d		# i
	provide Davs2		# d*
	provide Kvazaar		# c
	provide Vpx		# ic
	provide X264		# ic
	provide X265		# ic(8bit)
	provide Xavs2		# d*
	provide Xvid		# ic
	: # NOOP

	# * missing arm support
}

### Leave the rest as is ####################
installFfmpegToolingDependencies
compileSupportingLibs
compileImageLibs
compileAudioCodecs
compileVideoCodecs

# almost there
provide Ffmpeg

# fingers crossed
sanityCheck

# return when run in source mode
[ $SCRIPT_NAME == "compileFfmpeg-alpine.sh" ] && exit $RESULT || return $RESULT
