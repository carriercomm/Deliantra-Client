package DC::UI::ChatView;

use strict;
use utf8;

use Deliantra::Protocol::Constants;

our @ISA = DC::UI::Dockable::;

sub new {
   my $class = shift;

   my $self = $class->SUPER::new (
      can_close => 1,
      child     => (my $vbox = new DC::UI::VBox),
      @_,
   );

   $self->update_info ($self->{info});

   $vbox->add ($self->{txt} = new DC::UI::TextScroller (
      expand     => 1,
      font       => $::FONT_FIXED,
      fontsize   => $::CFG->{log_fontsize},
      indent     => -4,
      can_hover  => 1,
      can_events => 1,
      max_par    => $::CFG->{logview_max_par},
      tooltip    => $self->{text_tooltip},
   ));

   $vbox->add (my $hb = DC::UI::HBox->new);

   $hb->add (
      $self->{say_command_label} =
         DC::UI::Label->new (markup => $self->{say_command}));

   $hb->add ($self->{input} = DC::UI::Entry->new (
      expand      => 1,
      tooltip     => $self->{entry_tooltip},
      on_focus_in => sub {
         my ($input, $prev_focus) = @_;

         $::MESSAGE_WINDOW->set_visibility (1);
         delete $input->{refocus_map};

         if ($prev_focus == $::MAPWIDGET && $input->{auto_activated}) {
            $input->{refocus_map} = 1;
         }
         delete $input->{auto_activated};

         0
      },
      on_activate => sub {
         my ($input, $text) = @_;
         $input->set_text ('');

         return unless $::CONN;

         if ($text =~ /^\/(.*)/) {
            $::CONN->user_send ($1);
         } elsif (length $text) {
            my $say_cmd = $self->{say_command};
            $::CONN->user_send ($say_cmd . $text);
         } else {
            $input->{refocus_map} = 1;
         }
         if (delete $input->{refocus_map}) {
            $::MAPWIDGET->grab_focus;
         }

         0
      },
      on_key_down => sub {
         my ($input, $ev) = @_;
         my $uni = $ev->{unicode};
         my $mod = $ev->{mod};

         if ($uni >= ord "0" && $uni <= ord "9" && $mod & DC::KMOD_ALT) {
            $::MAPWIDGET->emit (key_down => $ev);
            return 1;
         }

         0
      },
      on_escape => sub {
         $::MAPWIDGET->grab_focus;

         0
      },
   ));

   $self->{initiated} = 1; # for update_info

   $self
}

# (private) This method updates the channel info associated with this chat view.
sub update_info {
   my ($self, $info) = @_;
   $self->{title}         = $info->{title};
   $self->{text_tooltip}  = $info->{tooltip};
   $self->{say_command}   = $info->{reply};
   $self->{entry_tooltip} =
      $info->{entry_tooltip}
      || "Enter a message and press enter to send it to the channel '$info->{title}'.";

   # TODO: needs some testing maybe, if known that this works: remove comment!
   if ($self->{initiated}) {
      $self->{say_command_label}->set_markup ($self->{say_command});
      $self->{txt}->{tooltip}   = $self->{text_tooltip};
      $self->{input}->{tooltip} = $self->{entry_tooltip};
      $self->set_title ($self->{title});
   }
}

# (private) This method overloads the set_dockbar_tab_active method of
# the Dockbar to capture the activation event of the tab. Mainly used
# to remove highlightin.
sub set_dockbar_tab_active {
   my ($self, $active) = @_;
   if ($active) {
      $self->set_inactive_fg (undef); # reset inactive color
   }
   $self->SUPER::set_dockbar_tab_active ($active);
}

# This method renders a message to the text field and sets highlighting
# and does other stuff that a message can cause.
sub message {
   my ($self, $para) = @_;

   if ($self->is_docked && !$self->is_docked_active) {
      if (($para->{color_flags} & NDI_COLOR_MASK) == NDI_RED) {
         $self->set_inactive_fg ([1, 0, 0]);
      } else {
         $self->set_inactive_fg ([0.6, 0.6, 1]);
      }
   }

   if ($para->{color_flags} & NDI_REPLY) {
      $self->select_my_tab;
   }

   if ($para->{color_flags} & NDI_CLEAR) {
      $self->clear_log;
   }

   my $time = sprintf "%02d:%02d:%02d", (localtime time)[2,1,0];

   $para->{markup} = "<span foreground='#ffffff'>$time</span> $para->{markup}";

   my $txt = $self->{txt};
   $txt->add_paragraph ($para);
   $txt->scroll_to_bottom;
}

# This method is called when 
sub activate {
   my ($self, $preset) = @_;

   $self->SUPER::activate ();

   $self->{input}->{auto_activated} = 1;
   $self->{input}->grab_focus;

   if ($preset && $self->{input}->get_text eq '') {
      $self->{input}->set_text ($preset);
   }
}

# sets the fontsize of the chats textview
sub set_fontsize {
   my ($self, $size) = @_;
   $self->{txt}->set_fontsize ($size);
}

# sets the maximum of paragraphs shown
sub set_max_par {
   my ($self, $max_par) = @_;
   $self->{txt}{max_par} = $max_par;
}

# clears the text log
sub clear_log {
   my ($self) = @_;

   $self->{txt}->clear;
}

1
