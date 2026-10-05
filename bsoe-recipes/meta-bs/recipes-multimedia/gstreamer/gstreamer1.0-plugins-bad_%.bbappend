# Minimal, valid Meson flags (enough for RTSP pipelines; h264parse is built by default)
EXTRA_OEMESON = " \
    -Dintrospection=disabled \
    -Dexamples=disabled \
    -Ddoc=disabled \
    -Dtests=disabled \
    -Dorc=enabled \
    -Dgir=disabled \
    -Dmpegtsdemux=enabled \
    -Dmpegts=disabled \
    -Dgst_codecs=disabled \
    -Dcodecparsers=disabled \
"

# Strip invalid/bogus options that break configure (defensive)
EXTRA_OEMESON:remove = "-Dvideoparsersbad=enabled"
EXTRA_OEMESON:remove = "-Dvideoparsersbad=disabled"

# Disable introspection completely
GI_DATA_ENABLED = "False"

# NOTE: encoding-profiles removal is intentionally NOT done here. The BrightSign
# OS source ships its own gstreamer1.0-plugins-bad_<version>.bbappend (under
# meta-bs/recipes-open/gstreamer/) that already removes ${datadir}/gstreamer-1.0.
# Adding a second removal here made two do_install:append blocks race: ours
# deleted the directory first, then the OS one's unguarded `rmdir` failed with
# "No such file or directory" and broke do_install. Leave the cleanup to the OS
# recipe.

# Keep PACKAGECONFIG minimal but don't override completely
PACKAGECONFIG:remove = " \
  gl x11 wayland qt5 vulkan nvcodec kms va \
  webrtc webrtcdsp sctp \
  openal opencv openjpeg openh264 msdk aom libde265 modplug assrender faac faad fluidsynth \
  dash hls smoothstreaming curl curl-ssh2 rtmp srt srtp \
  bz2 webp rsvg sndfile sbc uvch264 zbar x265 dtls ttml avtp directfb dc1394 neon \
  introspection mpegts codecs codecparsers \
"
