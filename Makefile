CROSS_COMPILE  = arm-nickel-linux-gnueabihf-
MOC            = moc
CC             = $(CROSS_COMPILE)gcc
CXX            = $(CROSS_COMPILE)g++
PKG_CONFIG     = $(CROSS_COMPILE)pkg-config

DESTDIR =

ifneq ($(if $(MAKECMDGOALS),$(if $(filter-out clean gitignore install koboroot,$(MAKECMDGOALS)),YES,NO),YES),YES)
 $(info -- Skipping configure)
else
PTHREAD_CFLAGS := -pthread
PTHREAD_LIBS   := -pthread

define pkgconf =
 $(if $(filter-out undefined,$(origin $(1)_CFLAGS) $(origin $(1)_LIBS)) \
 ,$(info -- Using provided CFLAGS and LIBS for $(2)) \
 ,$(if $(shell $(PKG_CONFIG) --exists $(2) >/dev/null 2>/dev/null && echo y) \
  ,$(info -- Found $(2) ($(shell $(PKG_CONFIG) --modversion $(2))) with pkg-config) \
   $(eval $(1)_CFLAGS := $(shell $(PKG_CONFIG) --silence-errors --cflags $(2))) \
   $(eval $(1)_LIBS   := $(shell $(PKG_CONFIG) --silence-errors --libs $(2))) \
   $(if $(3) \
   ,$(if $(shell $(PKG_CONFIG) $(3) $(2) >/dev/null 2>/dev/null && echo y) \
    ,$(info .. Satisfies constraint $(3)) \
    ,$(info .. Does not satisfy constraint $(3)) \
     $(error Dependencies do not satisfy constraints)) \
   ,) \
  ,$(info -- Could not automatically detect $(2) with pkg-config. Please specify $(1)_CFLAGS and/or $(1)_LIBS manually) \
   $(error Missing dependencies)))
endef

$(call pkgconf,QT5CORE,Qt5Core)
$(call pkgconf,QT5WIDGETS,Qt5Widgets)

CFLAGS   ?= -Wall -Wextra
CXXFLAGS ?= -Wall -Wextra
LDFLAGS  ?=

# temporary workaround for broken cflags in kobo-toolchain Docker image:
QT5CORE_CFLAGS    := $(shell echo "$(QT5CORE_CFLAGS)"    | sed 's:/toolchain/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/toolchain/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/:/toolchain/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/:g')
QT5WIDGETS_CFLAGS := $(shell echo "$(QT5WIDGETS_CFLAGS)" | sed 's:/toolchain/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/toolchain/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/:/toolchain/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/:g')
override CFLAGS   += -I/toolchain/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/include
override CXXFLAGS += -I/toolchain/arm-nickel-linux-gnueabihf/arm-nickel-linux-gnueabihf/sysroot/include

override CFLAGS   += -march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=hard -mthumb -std=gnu11
override CXXFLAGS += -march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=hard -mthumb -std=gnu++11
override LDFLAGS  += -Wl,-rpath,/usr/local/Kobo -Wl,-rpath,/usr/local/Qt-5.2.1-arm/lib
endif

all: src/libnmi.so

clean:
	rm -f $(GENERATED)

gitignore:
	echo '# make gitignore' > .gitignore
	echo '$(GENERATED)' | \
		sed 's/ /\n/g' | \
		sed 's/^./\/&/' >> .gitignore

install:
	install -Dm644 src/libnmi.so $(DESTDIR)/usr/local/Kobo/plugins/libnmi.so
	install -Dm644 res/doc $(DESTDIR)/mnt/onboard/.adds/nmi/doc

koboroot:
	make install DESTDIR=KoboRoot
	tar czf KoboRoot.tgz -C KoboRoot .; rm -rf KoboRoot

.PHONY: all clean gitignore install koboroot
override GENERATED += KoboRoot

src/libnmi.so: override CFLAGS   += $(PTHREAD_CFLAGS) -fPIC
src/libnmi.so: override CXXFLAGS += $(PTHREAD_CFLAGS) $(QT5CORE_CFLAGS) $(QT5WIDGETS_CFLAGS) -fPIC
src/libnmi.so: override LDFLAGS  += $(PTHREAD_LIBS) $(QT5CORE_LIBS) $(QT5WIDGETS_LIBS) -ldl -Wl,-soname,libnmi.so
src/libnmi.so: src/qtplugin.o src/init.o src/config.o src/dlhook.o src/failsafe.o src/menu.o src/subsys_c.o src/subsys_cc.o

override LIBRARIES += src/libnmi.so
override MOCS      += src/qtplugin.moc

define patw =
 $(foreach dir,src res,$(dir)/*$(1))
endef
define rpatw =
 $(patsubst %$(1),%$(2),$(foreach w,$(call patw,$(1)),$(wildcard $(w))))
endef

$(LIBRARIES): src/%.so:
	$(CC) -shared -o $@ $^ $(LDFLAGS)
$(MOCS): %.moc: %.h
	$(MOC) $< -o $@
$(patsubst %.moc,%.o,$(MOCS)): %.o: %.moc
	$(CXX) -xc++ $(CXXFLAGS) -c $< -o $@
$(call rpatw,.c,.o): %.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@
$(call rpatw,.cc,.o): %.o: %.cc
	$(CXX) $(CXXFLAGS) -c $< -o $@

override GENERATED += $(LIBRARIES)  $(MOCS) $(patsubst %.moc,%.o,$(MOCS)) $(call rpatw,.c,.o) $(call rpatw,.cc,.o)
