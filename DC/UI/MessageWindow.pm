package DC::UI::MessageWindow;

# Deprecated due to Dockbar

use strict;
use utf8;

use Scalar::Util qw/weaken/;
use DC::UI::ChatView;
use Deliantra::Protocol::Constants;

our @ISA = DC::UI::Toplevel::;

our %channel_info;

sub clr_def($)  { "<span foreground=\"#ffffff\">$_[0]</span>" }
sub clr_act($)  { "<span foreground=\"#ffffff\">$_[0]</span>" }
sub clr_hlt($)  { "<span foreground=\"#ffaaaa\">$_[0]</span>" }
sub clr_hlt2($) { "<span foreground=\"#ff0000\">$_[0]</span>" }

sub new {
   my $class = shift;

   my $self = $class->SUPER::new (
      name      => "message_window",
      title     => "Messages",
      border_bg => [1, 1, 1, 1],
      x         => "max",
      y         => 0,
      force_w   => $::WIDTH  * 0.4,
      force_h   => $::HEIGHT * 0.5,
      child     => (my $nb = DC::UI::Notebook->new (expand => 1)),
      has_close_button => 1
   );

   $self->{nb}        = $nb;
   $self->{chatviews} = {};

   $nb->connect (page_changed => sub {
      my ($nb, $page) = @_;
      $self->set_current_tab ($page);
   });
   $nb->connect (c_add => sub {
      $self->update_tabs;
   });

   my $l = $self->{main_log} =
      DC::UI::ChatView->new (expand => 1, say_command => '');

   $l->{_tab_label} =
      $l->{c_tab} =
         DC::UI::Button->new (
            markup => "Log", tooltip => "This is the main log of the server."
         );

   $nb->add ($l);
   $nb->set_current_page ($l);

   $self
}

sub add_chat {
   my ($self, $id) = @_;

   my $chatviews = $self->{chatviews};
   my $chaninfo  = $self->{channel_info}->{$id};
   my $nb        = $self->{nb};

   my $cv = $chatviews->{$id} =
      DC::UI::ChatView->new (
         expand        => 1,
         say_command   => $chaninfo->{reply},
         entry_tooltip => $chaninfo->{tooltip},
         text_tooltip  => "Conversation with $chaninfo->{title}"
      );

   my $bb = DC::UI::ButtonBin->new (tooltip => $chaninfo->{tooltip});
   $cv->{c_tab} = $bb;

   $bb->add (my $vb = DC::UI::Box->new);
   $vb->add (
      my $b = DC::UI::Label->new (
         expand => 1, markup => clr_def ($chaninfo->{title}),
      )
   );

   $cv->{_chat_id} = $id;
   $cv->{_tab_label} = $b;
   weaken $cv->{_tab_label};

   $vb->add (
      my $b = DC::UI::ImageButton->new (
         path  => 'x1_close.png',
         scale => 0.3,
      )
   );
   $b->connect (activate => sub {
      my $b = shift;
      $self->close_chatview ($cv);
      0
   });

   my $preadd = $nb->get_current_page;
   $nb->add ($cv);
   $nb->set_current_page ($preadd);
}

sub close_chatview {
   my ($self, $cv) = @_;
   return unless defined $cv->{_chat_id};

   my $chatviews = $self->{chatviews};
   my $nb = $self->{nb};
   my @chld = $nb->pages;
   my $cur = pop @chld;
   while (@chld && $cur != $cv) {
      $cur = pop @chld;
   }
   $cur = pop @chld;
   $nb->remove ($cv);
   $nb->set_current_page ($cur);

   delete $chatviews->{$cv->{_chat_id}};
}

sub touch_channel {
   my ($self, $id) = @_;

   if (not exists $self->{chatviews}->{$id}) {
      $self->add_chat ($id);
   }
}

sub highlight_channel {
   my ($self, $id, $hlt_func) = @_;

   $hlt_func ||= \&clr_hlt;

   my $cv = $self->{chatviews}->{$id};

   # the clr_hlt2 has a "higher priority"
   unless ($cv->{_channel_highlighted} eq \&clr_hlt2) {
      $cv->{_channel_highlighted} = $hlt_func;
   }

   $self->update_tabs;
}

sub set_current_tab {
   my ($self, $page) = @_;

   for ($self->{nb}->pages) {
      next if $_ eq $page;
      $_->{_active} = 0;
   }
   $page->{_active} = 1;

   $self->update_tabs;
}

sub close_current_tab {
   my ($self) = @_;
   $self->close_chatview ($self->{nb}->get_current_page);
}

sub update_tabs {
   my ($self) = @_;

   my $i = 1;
   for ($self->{nb}->pages) {
      if ($i <= 10) {
         $_->{_tab_pos} = $i++;
      } else {
         $_->{_tab_pos} = undef;
      }

      my $tab = $_->{_tab_label};
      next unless $tab;

      my ($label, $tooltip) =
         ("Log", "This is the main log of the server.");

      if (defined $_->{_chat_id}) {
         my $chinfo = $self->{channel_info}->{$_->{_chat_id}};
         $label     = $chinfo->{title};
         $tooltip   = $chinfo->{tooltip};

         if ($_->{_active}) {
            $_->{_channel_highlighted} = 0;
         }
      }

      $_->{c_tab}->set_tooltip (
         $tooltip
         . (defined $_->{_tab_pos}
               ? "\n\n<small>Alt+"
                 . ($_->{_tab_pos} == 10 ? '0' : $_->{_tab_pos})
                 . " - activates this tab.\n"
                 . "Return - toggles activity of the entry."
                 . "</small>"
               : "")
      );

      my $hltfunc = $_->{_channel_highlighted}
                    || ($_->{_active} ? \&clr_act : \&clr_def);

      $tab->set_markup (
         $hltfunc->($label . (defined $_->{_tab_pos} ? "\-$_->{_tab_pos}" : ""))
      );
   }
}

sub add_channel {
   my ($self, $info) = @_;

   $self->{channel_info}->{$info->{id}} = $info;
   $self->touch_channel ($info->{id});
}

sub message {
   my ($self, $para) = @_;

   #d# require Data::Dumper;
   #d# print "FOO[".Data::Dumper->Dump ([$para])."]\n";

   my $id = $para->{type};

   if (exists $self->{channel_info}->{$id}) {
      $self->touch_channel ($id);

      if (my $cv = $self->{chatviews}->{$id}) {

         if ($cv != $self->{nb}->get_current_page) {

            if (($para->{color_flags} & NDI_COLOR_MASK) == NDI_RED) {
               $self->highlight_channel ($id, \&clr_hlt2);
            } else {
               $self->highlight_channel ($id);
            }
         }

         if ($para->{color_flags} & NDI_REPLY) {
            $self->{nb}->set_current_page ($cv);
         }

         if ($para->{color_flags} & NDI_CLEAR) {
            $cv->clear_log;
         }
      }

      $self->{chatviews}->{$id}->message ($para);

   } else {
      $self->{main_log}->message ($para);
   }
}

sub activate_console {
   my ($self, $preset) = @_;

   $self->{main_log}->activate_console ($preset);
}

sub activate_current {
   my ($self) = @_;

   $self->{nb}->get_current_page->activate_console;
}

sub set_fontsize {
   my ($self, $size) = @_;

   for (values %{$self->{chatviews}}, $self->{main_log}) {
      $_->set_fontsize ($size);
   }
}

sub set_max_par {
   my ($self, $max_par) = @_;

   for (values %{$self->{chatviews}}, $self->{main_log}) {
      $_->set_max_par ($max_par);
   }
}

sub user_switch_to_page {
   my ($self, $page) = @_;

   $page = $page eq '0' ? 10 : $page;

   my @tabs = $self->{nb}->pages;

   for (my $i = 0; $i < ($page - 1); $i++) {
      shift @tabs;
   }

   my $page = shift @tabs;
   return unless $page;

   $self->{nb}->set_current_page ($page);
}

1

