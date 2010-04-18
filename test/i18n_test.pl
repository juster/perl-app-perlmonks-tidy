my $decimal   = '.';    # decimal point indicator for "natural_sort"
my $separator = ',';    # thousands separator for "natural_sort"

# deaccent will force sorting of Latin-1 word characters above \xC0 to be
# treated as their base or equivalent character.
sub deaccent {
    my $phrase = shift;
    return $phrase unless ( $phrase =~ y/\xC0-\xFF// ); #short circuit if no upper chars
    # translterate what we can (for speed)
    $phrase =~ tr/ÀÁÂÃÄÅàáâãäåÇçÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÑñÙÚÛÜùúûüİÿı/AAAAAAaaaaaaCcEEEEeeeeIIIIiiiiOOOOOOooooooNnUUUUuuuuYyy/;
    # and substitute the rest
    my %trans = qw(Æ AE æ ae Ş TH ş th Ğ TH ğ th ß ss);
    $phrase =~ s/([ÆæŞşĞğß])/$trans{$1}/g;
    return $phrase;
}

# no-sep will allow the sorting algorithm to ignore (mostly) the presence
# of thousands separators in large numbers. It is configured by default
# to be comma, but can be changed to whatever is desired. (a likely possibility is .)
sub no_sep {
    my $phrase = shift;
    $phrase =~ s/\Q$separator\E//g;
    return $phrase;
}

# Very fast natural sort routine. If (not) desired, delete the no-sep and deaccent
# modifiers to remove those effects.
sub natural_sort {
    my $i;
    no warnings q/uninitialized/;
    s/((\Q$decimal\E0*)?)(\d+)/("\x0" x length $2) . (pack 'aNa*', 0, length $3, $3)/eg, $_ .= ' ' . $i++ for ( my @x = map { lc deaccent no_sep $_} @_ );
    @_[ map { (split)[-1] } sort @x ];
}

