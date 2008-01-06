package DC::Pod;

use strict;
use utf8;

use Storable;

our $VERSION = 1.03;

our $goto_document = sub { };
our %wiki;

my $MA_BEG = "\x{fcd0}";
my $MA_SEP = "\x{fcd1}";
my $MA_END = "\x{fcd2}";

*wiki = Storable::retrieve DC::find_rcfile "docwiki.pst";

sub goto_document($) {
   $goto_document->(split /\//, $_[0]);
}

sub is_prefix_of($@) {
   my ($node, @path) = @_;

   return 1 unless @path;

   my $kw = lc pop @path;

   $node = $node->{parent}
      or return 0;

   return ! ! grep $_ eq $kw, @{ $node->{kw} };
}

sub find(@) {
   my (@path) = @_;

   return unless @path;

   my $kw = lc pop @path;

   # TODO: make sure results are unique

   grep { is_prefix_of $_, @path }
      map @$_,
         $kw eq "*" ? @wiki{sort keys %wiki}
                    : $wiki{$kw} || ()
}

sub full_path_of($) {
   my ($node) = @_;

   my @path;

   # skip toplevel hierarchy pod/, because its not a document
   while ($node->{parent}) {
      unshift @path, $node;
      $node = $node->{parent};
   }

   @path
}

sub full_path($) {
   join "/", map $_->{kw}[0], &full_path_of
}

sub section_of($) {
   my ($node) = @_;

   my $doc = $node->{doc};
   my $par = $node->{par};
   my $lvl = $node->{level};

   my @res;

   do {
      my $p = $doc->[$par];

      if (length $p->{markup}) {
         push @res, {
            markup => $p->{markup},
            indent => $p->{indent},
         };
      }
   } while $doc->[++$par]{level} > $lvl;

   @res
}

sub section(@) {
   map section_of $_, &find
}

sub thaw_section(\@\%) {
   for (@{$_[0]}) {
      $_->{markup} =~ s{
         $MA_BEG
         ([^$MA_END]+)
         $MA_END
      }{
         my ($type, @arg) = split /$MA_SEP/o, $1;

         $_[1]{$type}($_, @arg)
      }ogex;
   }
}

my %as_label = (
   image => sub {
      my ($par, $path) = @_;

      "<small>img</small>"
   },
   link => sub {
      my ($par, $text, $link) = @_;

      "<span foreground='#ffff00'>↺</span><span foreground='#c0c0ff' underline='single'>" . (DC::asxml $text) . "</span>"
   },
);

sub as_label(@) {
   thaw_section @_, %as_label;

   my $text =
      join "\n",
         map +("\xa0" x ($_->{indent} / 4)) . $_->{markup},
            @_;

   $text =~ s/^\s+//;
   $text =~ s/\s+$//;

   $text
}

my %as_paragraphs = (
   image => sub {
      my ($par, $path, $flags) = @_;

      push @{ $par->{widget} }, new DC::UI::Image path => $path,
         $flags & 1 ? (max_h => $::FONTSIZE) : ();

      "\x{fffc}"
   },
   link => sub {
      my ($par, $text, $link) = @_;

      push @{ $par->{widget} }, new DC::UI::Label
         markup     => "<span foreground='#ffff00'>↺</span><span foreground='#c0c0ff' underline='single'>" . (DC::asxml $text) . "</span>",
         fontsize   => 0.8,
         can_hover  => 1,
         can_events => 1,
         padding_x  => 0,
         padding_y  => 0,
         tooltip    => "Go to <i>" . (DC::asxml $link) . "</i>",
         on_button_up => sub {
            goto_document $link;
         };

      "\x{fffc}"
   },
);

sub as_paragraphs(@) {
   thaw_section @_, %as_paragraphs;

   @_
}

sub section_paragraphs(@) {
   as_paragraphs &section
}

sub section_label(@) {
   as_label &section
}

1
