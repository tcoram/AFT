: # use perl                                  -*- mode: Perl; -*-
	eval 'exec perl -S $0 "$@"'
		if $running_under_some_shell;

#
# compile.pl - AFT element file compiler.
#
# Copyright (C) 1996-2003 Todd Coram.  All rights reserved.

my $VERSION="2.07";

# Hash of elements
my %element = ();

# Hash of variables
my %postvar = ();

my $preamble;
my $postamble;

my $subs = '';

my $postfilter;
my $prefilter;

$date = scalar localtime;

(@ARGV == 0) && do {
    print (STDERR "Usage: aft-compile element_file.dat \n");
    exit 2;
};

$infile = $ARGV[0];
$outfile = $ARGV[0];
$outfile =~ s/([^.])\.dat$/$1\.pm/;

open(OUT, ">$outfile") || die "Can't open $outfile for output!";

select(OUT);

print (STDERR "Compiling $infile into $outfile ...\n");
print "# AFT Output Elements.\n";
print "# !!DO NOT EDIT!! This file was automatically generated by aft-compile ";
print "v$VERSION on $date\n";
print "# See http://www.maplefish.com/todd/aft.html for details.\n";

&processFile($infile);

sub processFile {
    my ($fname) = @_;
    local *IN;
    open(IN, $fname) || die "Can't open data file: $fname";

    my $inPreamble = 0;


    while (<IN>) {
	chop;
	# Skip comment lines
	next if (/^(\s*\#|\Z)/ && !$inPreamble &&  !$inPostamble && !$inSubs);

	# Single line sub
	/^sub (.+)/ && do {
	    $subs .= "sub $1\n";
	};

	/^use (.+)/ && do {
	    print STDERR "Using features from $1...\n";
	    print "\n# Using features from $1.\n";
	    &processFile($1);
	};

	# Enter and exit preambles and postambles states.
	#
	/^\s*Preamble\s*\{/ && ($inPreamble = 1, $preamble = '', next);
	/^\s*\}\s*Preamble/ && ($inPreamble = 0, next);
	/^\s*Postamble\s*\{/ && ($inPostamble = 1, $postamble = '', next);
	/^\s*\}\s*Postamble/ && ($inPostamble = 0, next);

	/^\s*Subs\s*\{/ && ($inSubs = 1, next);
	/^\s*\}\s*Subs/ && ($inSubs = 0, next);
    
	# Read in the preamble and postamble text.
	#
	$inPreamble && ($preamble .= $_."\n", next);
	$inPostamble && ($postamble .= $_."\n", next);

	$inSubs && ($sub .= $_."\n", next);

        # Parse: preFilter into pairs (stored one after other in the array).
	#
	/^\s*(preFilter)\s+([^\s]+)\s*([^\s]*)/ && do {
	    push(@prefilter, "\$line=~s/$2/$3/g;");
	    next;
	};
	/^\s*(preFilter\/e)\s+([^\s]+)\s*([^\s]*)/ && do {
	    push(@prefilter, "\$line=~s/$2/$3/ge;");
	    next;
	};

	# Parse: postFilter into pairs (stored one after other in the array).
	#
	/^\s*(postFilter)\s+([^\s]+)\s+([^\s]+)/ && do {
	    push(@postfilter, "\$line=~s/$2/$3/g;");
	    next;
	};

	/^\s*(postFilter\/e)\s+([^\s]+)\s+([^\s]+)/ && do {
	    push(@postfilter, "\$line=~s/$2/$3/ge;");
	    next;
	};

	# Post filtering variables
	#
	/^SET\s+(\w+)\s*=\s*/ && ($postvar{$1} = $', next);

	# Elements
	#
	/^\s*([^\s]+)\s*/ && ($element{$1} = $');
    }
    close(IN);
}


print "package AFT_OUTPUT;\n\n";
print 'use vars qw ($file_preamble $file_postamble %elem %pragma_postvar);'."\n\n";
print '$file_preamble = \'\';	# Holds preamble for output file.'."\n";
print '$file_postamble = \'\';	# Holds postamble for output file.'."\n";
print '%elem = ();		# Element commands for producing output file.';
print '%pragma_postvar = ();	# Variables for substitution post-filtering.'."\n";
print "\n\nsub init_elements {\n";

$interpolate = ($element{"interpolate"} =~ 'no') ? 0 : 1;
print "\t\%pragma_postvar = (\n";
foreach $item (keys %postvar) {
    print "\t\t'$item' =>\t '$postvar{$item}',\n";
}
print "\t);\n";

print "\t\%elem = (\n";
foreach $item  (keys %element) {
  if ($element{$item} =~ /^\<Undefined/) {
    print (STDERR "Undefined element: [$item]\n");
  }
  if ($interpolate && $item ne "PostProcessor") {
    # Quote nasty things they may get in the way
    $element{$item} =~ s/([\'\@\$\%])/\\$1/g; 
    print "\t\t'$item' =>\t qq'$element{$item}',\n";
  } else {
    $element{$item} =~ s/([\'])/\\$1/g; 
    print "\t\t'$item' =>\t '$element{$item}',\n";
    }
}
print "\t);\n";


print "\n## Preamble:\n\n";
$preamble =~ s/([\'])/\\$1/g; 
print "\$file_preamble = '$preamble';\n";
print "\n## Postamble:\n\n";
$postamble =~ s/([\'])/\\$1/g; 
print "\$file_postamble = '$postamble';\n";

print "}\n\n";

print "\n## Prefilter subroutine:\n\n";

print "sub prefilter {\n";
print "   my (\$line) = \@_;\n";
print "   ".join("\n   ", @prefilter);
print "\n   return \$line;\n}\n";

print "\n## Postfilter subroutine:\n\n";

print "sub postfilter {\n";
print "   my (\$line) = \@_;\n";
print "   ".join("\n   ", @postfilter);
print "\n   return \$line;\n}\n";
print "\n $subs\n";
print "\n1;\n";
