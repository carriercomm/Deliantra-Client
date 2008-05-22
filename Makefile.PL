use ExtUtils::MakeMaker;

sub manifest_resources {
   open my $manifest, "MANIFEST" or die "Couldn't open MANIFEST: $!";
   map { chomp; $_ } grep /^resources\//, <$manifest>
}

print <<EOF;

*** opengl 1.1 is required to run this client
*** opengl 1.2 is recommended to run this client
*** opengl 2.0 helps some more....

*** other dependencies:
*** pango-1.12.3, glib-2.10
*** libsdl, libSDL_mixer, libSDL_image

*** Pod::POM, Compress::LZF, BDB, Deliantra, EV, AnyEvent perl modules

*** HINT: Debian/Ubuntu users might have some luck with:
*** apt-get install perl libpango1.0-dev libglib2.0-dev libsdl1.2-dev
*** apt-get install libsdl-mixer1.2-dev libsdl-image1.2-dev
*** apt-get install libwww-perl libdb4.4-dev
*** apt-get install anyevent-perl

EOF

if ($^O =~ /win32/i or $^O =~ /mswin/) {
   print <<EOF;
*** microsoft compatibility forced us to only support manual configuration
*** by editing Makefile.PL. complain to microsoft.

EOF
   $INC  = "-I/gtk/include -I/gtk/include/pango-1.0 -I/gtk/include/glib-2.0 -I/gtk/lib/glib-2.0/include/ -I/gtk/include/freetype2";
   $LIBS = "-L/gtk/lib -lSDL -lSDL_image -lSDL_mixer -lpango-1.0 -lpangoft2-1.0 -lgobject-2.0 -lgmodule-2.0 -lglib-2.0 -lfreetype -lfontconfig -lopengl32 -lwininet",
} else {
   $INC  = join " ", qx<sdl-config --cflags>, qx<pkg-config pangoft2 --cflags>;
   $LIBS = join " ", qx<sdl-config --libs>, "-lSDL_image -lSDL_mixer", qx<pkg-config pangoft2 --libs>, "-lGL";

   $INC =~ s/\n/ /g for $INC, $LIBS;
}

WriteMakefile(
    dist	=> {
	            PREOP	=> 'pod2text bin/deliantra | tee README >$(DISTVNAME)/README; chmod -R u=rwX,go=rX . ;',
	            COMPRESS	=> 'gzip -9v',
	            SUFFIX	=> '.gz',
	           },
    NAME => "Deliantra::Client",
    INC => $INC,
    LIBS => [$LIBS],
    EXE_FILES => [qw(bin/deliantra)],
    VERSION_FROM => "DC.pm",
    PREREQ_PM => {
       BDB           => 1.45,
       Deliantra     => 1.13,
       Time::HiRes   => 0,
       EV            => 3.41,
       AnyEvent      => 2.6,
       Compress::LZF => 1.6,
       Pod::POM      => 0.15,
       LWP           => 0,
       JSON::XS      => 2.01,
    },
    depend    => {
       "Client.o" => 'glfunc.h pangoopengl.h pango-font.c pango-fontmap.c pango-render.c texcache.c rendercache.c',
    },
    clean     => { FILES => 'docwiki.pst' },
    PM => {
       'DC.pm'                    => '$(INST_LIBDIR)/Client/private/DC.pm',
       'DC/Protocol.pm'           => '$(INST_LIBDIR)/Client/private/DC/Protocol.pm',
       'DC/OpenGL.pm'             => '$(INST_LIBDIR)/Client/private/DC/OpenGL.pm',
       'DC/Texture.pm'            => '$(INST_LIBDIR)/Client/private/DC/Texture.pm',
       'DC/DB.pm'                 => '$(INST_LIBDIR)/Client/private/DC/DB.pm',
       'DC/UI.pm'                 => '$(INST_LIBDIR)/Client/private/DC/UI.pm',
       'DC/MessageDistributor.pm' => '$(INST_LIBDIR)/Client/private/DC/MessageDistributor.pm',
       'DC/UI/Canvas.pm'          => '$(INST_LIBDIR)/Client/private/DC/UI/Canvas.pm',
       'DC/UI/Dockable.pm'        => '$(INST_LIBDIR)/Client/private/DC/UI/Dockable.pm',
       'DC/UI/Dockbar.pm'         => '$(INST_LIBDIR)/Client/private/DC/UI/Dockbar.pm',
       'DC/UI/Inventory.pm'       => '$(INST_LIBDIR)/Client/private/DC/UI/Inventory.pm',
       'DC/UI/SpellList.pm'       => '$(INST_LIBDIR)/Client/private/DC/UI/SpellList.pm',
       'DC/UI/Canvas.pm'          => '$(INST_LIBDIR)/Client/private/DC/UI/Canvas.pm',
       'DC/UI/ChatView.pm'        => '$(INST_LIBDIR)/Client/private/DC/UI/ChatView.pm',
       'DC/UI/MessageWindow.pm'   => '$(INST_LIBDIR)/Client/private/DC/UI/MessageWindow.pm',
       'DC/Item.pm'               => '$(INST_LIBDIR)/Client/private/DC/Item.pm',
       'DC/Pod.pm'                => '$(INST_LIBDIR)/Client/private/DC/Pod.pm',
       'DC/MapWidget.pm'          => '$(INST_LIBDIR)/Client/private/DC/MapWidget.pm',
       'DC/Macro.pm'              => '$(INST_LIBDIR)/Client/private/DC/Macro.pm',
       'docwiki.pst'              => '$(INST_LIBDIR)/Client/private/resources/docwiki.pst',
       (map +($_ => "\$(INST_LIBDIR)/Client/private/$_"), manifest_resources),
    }
);

sub MY::postamble {
   my $self = shift;

   # try to add MANIFEST to CONFIGDEP
   s/^CONFIGDEP = /CONFIGDEP = MANIFEST /m
      for @{ $self->{RESULT} };

   my $pods = join " ", <pod/*.pod>;

   <<EOF

all :: docwiki.pst

docwiki.pst: bin/pod2wiki $pods
	\$(PERL) -Mlib=. bin/pod2wiki $pods

EOF
}

