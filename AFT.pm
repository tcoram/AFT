# Almost Free Text (AFT) Parser
#
# Copyright (C) 1996-2010 Todd A. Coram. All rights reserved.
#
# This perl script parses aft documents and produces output formatted according
# to an aft 'element' file.  See aft-refman.aft  for additional information.
#

use strict; 
no strict "refs";

package AFT;

use English;
use vars qw ($VERSION $version $outputfile $element_type $author $title
	     $pre_process_line $my_print);

# Initializations of globals that consumers of this package may read/modify.
#

$author = '';
$title = '';
$VERSION="v5.098";
$version=
  "Almost Free Text $VERSION; Copyright 1996-2010 Todd Coram.";

$element_type="bn-html";		# Default
$outputfile='';			# Output file

# You can supply your own pre-processor here... For now, here is a NOOP.
# This is of interest to apps that use AFT.pm as a package. 
#
$pre_process_line = sub { local $_ = shift; my($fname,$lcnt) = @_; return $_; };
# You can supply your own print subroutine here.
#
$my_print = sub { print @_; };

# Package scoped variables.
#

my $aft_advert =
  "This document was generated using {-AFT $VERSION\@http://www.maplefish.com/todd/aft.html-}";

my $autonumber =0;		# prefix sections with nested numbers 
my $verbose = 0;		# Spew out lots of rambling commentary?
my $tabstop=8;			# Default number of spaces constituting a tab.
my $holding_preamble = 1;	# True if we have not outputted title/author.


# Holds file handle for table of contents output
#
my $tocout;

#
# Global State (modes). This controls the AFT state machine.
#
my $mode = 
{
 processing_input => 1,	       # Are we processing input or dumping results?
 in_table => 0,			# Are we in table mode?
 need_table_headers => 0,		# Used to keep track of table building.
 eat_sep => 0,		# Used to eat a table separator line.
 in_quote => 0,			# Are we in quote mode?
 in_verb => 0,		# Are we in verbatim mode?
 in_blocked_verb => 0,		# Are we in blocked verbatim mode?
 in_filtered_verb => 0,		# Are we in filtered verbatim mode?
 in_para => 0,		# Paragraph mode indicator
 in_list_el => 0,		# Are we inside of a list element?
 cur_sect_level => 0,      # Current section we are in.
 in_sect => 0,		# True if we ever go into sections...
};

# Cache (memo) variables. Not state, but artifact used by states.
#
my $table_caption = '';		# Holds current table's caption.
my @list_stack;			# A stack of lists as we nest.
my @section_stack;		# Keeps track of nesting sections.
my $section_number = Autonum->new();

my %index;			# Hash of arrays (name -> [ ref, ... ])

my @note;			# Holds collected 'endnotes'.


#
# Submodes for paragraph mode.
#
my $paragraph =
{
 small => 0,
 strong => 0,
 emphasize => 0,
 teletype => 0,
};

my $face = 
{
    "|" => "Teletype",
    "''" => "Emphasis",
    "_" => "Strong",
    "~" => "Small",
};


# Pragma variables (set from inside documents)
#
my %pragma_prevar = ();		# variables expanded before filtering.
my %pragma_ctl = ();		# variables used for internal control

# Set up some convenient symbols %%
#
sub setup_symbols {
  $pragma_prevar{'lb'} = $AFT_OUTPUT::elem{'LineBreak'};
  $pragma_prevar{'sp'} = $AFT_OUTPUT::elem{'NBSPACE'};
  $pragma_prevar{'bang'} = '!';
}


# Don't expand pragmas in verbatim mode.
#
$AFT_OUTPUT::pragma_ctl{expandinverbatim} = 'no';

# Ignore square brackets as hyperlink indicators
#
$AFT_OUTPUT::pragma_ctl{verbatimsquarebrackets} = 'no';

# Turn on/off pre and post filtering
#
$AFT_OUTPUT::pragma_ctl{prefilter} = 'yes';
$AFT_OUTPUT::pragma_ctl{postfilter} = 'yes';

# AFT functions
#
my @Functions = (
	      \&handle_blocked_verbatim, # Must be before first...
	      \&handle_comments, # Must be first
	      \&handle_title_preamble, # Must be second
	      \&handle_includes,
	      \&handle_image,
	      \&handle_ruler,
	      \&handle_sections,
	      \&handle_lists,
	      \&handle_centered_text,
	      \&handle_quoted_text,
	      \&handle_table,
	      \&handle_verbatim,
	     );


# Run AFT from the command line. (The normal way to invoke AFT)
#
sub main {
    parse_command_line();
    load_element_file(element_file());
    setup_symbols();

    if ($outputfile eq '') {
        # Use first input filename to construct output filename.
	#
        $outputfile = $ARGV[0];
	$outputfile =~ s/\.\w+$//; # remove last '.' and anything following.
	$outputfile .= ".".lc($AFT_OUTPUT::elem{
	    defined $AFT_OUTPUT::elem{'EXT'} ? 'EXT' : 'ID'});
    }
    
    # Try and open output file and set it as the default output.
    #
    open(OUT, ">$outputfile") or die "Can't open $outputfile for output!\n";
    select(OUT);

    # Announce
    #
    print(STDERR 
      "$version\n  Writing $element_type output into $outputfile using". 
	  " $INC{element_file()}.\n") if $verbose;


    begin();

    # Process each file supplied on the command line.
    #
    foreach my $filename (@ARGV) {
	process_file($filename);
    }

    end();

    close(OUT);
    close($tocout) if $tocout; # If we wrote a table of contents, close it.
        
    if (my $post_processor = $AFT_OUTPUT::elem{'PostProcessor'}) {
	print(STDERR "\nPost Processing with '$post_processor'\n")
	    and eval $post_processor
	    or die "Can't post process $outputfile $!\n";
    }

    exit 0;
}


sub begin {
    # Initialize our state.
    #
    reset_states();

    # Hold onto the preamble 'til we see if *Title and *Author info is present.
    #
    $holding_preamble = 1;
    $mode->{processing_input}  = 1;
}

# Run AFT on a file given its filename.
#
sub do_file {
    my($filename) = @_;
    load_element_file(element_file());
    begin();
    process_file($filename);
    end();
}

# Run AFT on a single line supplied as a string (with a reference filename
# and line number-- both can be fake.)
#
sub do_string {
    local $_ = shift;
    my ($fname, $lcnt) = @_;
    
    $_ = $pre_process_line->($_, $fname, $lcnt);


    # Convert every $tabstop spaces into a tab... e.g. /\ {4}/
    s/\ {$tabstop}/\t/g if (!$mode->{in_blocked_verb});
    
    # Iterate through all functions until one satisfies the input.
    #
    foreach my $function (@Functions) {
	return if ($function->($fname, $lcnt, $_));
    }

    # All non-tabbed, non-sectional, non-special lines end up here.
    #
    
    # Always reset states
    # (take us out of whatever mode we may have been in).
    #
    reset_states();
    
    # Now handle a special case... We need to detect blank lines to
    # determine whether we should end paragraph mode.
    #
    reset_paragraph(), return if $_ eq '';
    
    # Otherwise, if not in paragraph mode, enter paragraph mode now.
    #
    enter_paragraph() if !$mode->{in_para};
    
    # and  kick out the filtered line.
    #
    output(filter($_)."\n");
}

# Run AFT on a file given its file handle.
#
sub do_FH_file {
    my($fh, $filename) = @_;
    load_element_file(element_file());
    begin();
    process_FH_file($fh, $filename);
    end();
}


sub output_preamble {
    output($AFT_OUTPUT::file_preamble."\n",
	    title => $title, author => $author, version => $version);
}

sub output_postamble {
    output($AFT_OUTPUT::file_postamble."\n", aft => filter($aft_advert));
}

sub output_indices {
  return if (%index == 0);	# no indexed words

  if (defined($AFT_OUTPUT::elem{'PrintIndex'})) {
      output($AFT_OUTPUT::elem{'PrintIndex'}."\n");
      return;
  }
  output($AFT_OUTPUT::elem{'HorizontalLine'}."\n");
  do_string("* Index");
  do_string("\n");
  foreach my $key (sort(keys %index)) {
    next if ($key =~ /iNtErNaLNOTE/);
    output($AFT_OUTPUT::elem{'LineBreak'});
    output("${key} : ");
    foreach my $target (@{$index{$key}}) {
      do_string("[*($target)], ");
    }
  }
}

sub output_notes {
    output($AFT_OUTPUT::elem{'HorizontalLine'}."\n");
    my $count = 1;
    foreach my $note (@note) {
	do_string("=[(iNtErNaLNOTE$count)]=\n\\[[$count(REFiNtErNaLNOTE$count)]] - $note\n");
	output($AFT_OUTPUT::elem{'LineBreak'});
	$count++;
    }
}

sub end {
    # End all modes.
    #
    reset_states();
    $mode->{processing_input}  = 0;

    # If we ever entered sections...

    enter_section(0), output($AFT_OUTPUT::elem{'EndSectLevel1'}."\n")
	if ($mode->{in_sect});
    
    output_notes() if ($AFT_OUTPUT::elem{'NotesAtEnd?'} eq 'yes');
    output_indices();

    # End output file with Postamble..
    #
    output_postamble();
}

sub parse_command_line {
    ## Process the command line options.
    #
    my $usage=
	"Usage:\n aft [--autonumber] [--verbose] [--output=file | --output=-]".
	" [--type=output_type] infile ..";

    use Getopt::Long;
    GetOptions ("output=s" => \$outputfile, # output file name
		"verbose!" => \$verbose, # output type (html, etc) 
		"type=s" => \$element_type, # output type (html, etc)
		"autonumber!" => \$autonumber, # section numbers
		"tabstop=i" => \$tabstop); # number of spaces = tab

    print (STDERR "$version\n$usage\n"), exit 2 if (@ARGV == 0);
}

sub element_file {
    return "aft-".$element_type.".pm";
}

# loadElementFile(file) - load the supplied element file name.
#
sub load_element_file {
    my $elementfile = shift;
    # This is more of an '#include' than a package import.
    eval
	{require $elementfile};	# Sets 3 variables in a subroutine
				# called initElements() and adds 2 additional
				# subroutines: prefilter() and postfilter().
    die "Can't locate $elementfile. \n\t(I looked in: @INC)\n" if $@;

    # Initialize elements;
    #
    AFT_OUTPUT::init_elements();
}

# processFile(fname) - Locate, open and process the supplied file.
#
sub process_file {
    my($fname) = @_;
    local *IN;
    if (!open(*IN, $fname)) {
	$fname .= ".aft";		# maybe we just got a a base name?
	open(*IN, $fname) or ((warn "Can't open $fname: $!\n"), return -1);
    }
    
    # Do that voodoo that you do so well.
    #
    print (STDERR "\nProcessing $fname.\n[") if $verbose;
    process_FH_file(*IN, $fname);
    
    # Done with it, so close it.
    #
    close (*IN);
    print (STDERR "]\nFinished processing $fname.\n") if $verbose;
    return 0;
}


# processFH_File (fh,fname) - Process the supplied file by the handle.
#
sub process_FH_file {
    my($fh, $fname) = @_;
    my $lcnt  = 0;		# line count
    
    my $continued_line = "";
    LINE: while (<$fh>) {
	$lcnt++;
	chomp;
	chop if /.*\r$/;  # In case we are unix perl processing a MSDOS .aft file
	$continued_line .= $1, next LINE if (/(.*)\\$/ and !$mode->{in_verb}); # collect continuations
	do_string($continued_line.$_, $fname, $lcnt); # process complete line
	$continued_line = "";
    }
    do_string($continued_line, $fname, $lcnt) if $continued_line;
}


##### Functions
#


# Handle comments and comment commands
#
sub handle_comments {
    my $fname = shift; my $lcnt = shift; local($_) = @_;
    
    # Handle Strike lines (X---)
    #
    /^X-{3,}([^\-]?.*)/ and do {
	output($AFT_OUTPUT::elem{'StrikeLine'}."\n",line => $1);
	return 1;
    };
    
    # Handle comments and comment commands (pragmas).
    #
    
    /^[C\#]-{3,}([^\-]?.*)/ and do {
	# See if there is stuff we need to pass directly through the filters.
	# #---PASS-'ID' text
	#
	$1 =~ /PASS-(\w+)\s+(.*)/ and do {
	    output($2) if ($AFT_OUTPUT::elem{'ID'} eq $1);
	    return 1;
	};
	
	# Set a pragma variable..
	# #---SET[-ID] var=value
	#
	$1 =~ /SET(\s?|-\w+)\s*([^\=\ ]+)\s*=\s*(.*)/ and do {
	    # Special control variable
	    $AFT_OUTPUT::pragma_ctl{$2} = $3 if ($1 eq "-CONTROL");

	    if ("-$AFT_OUTPUT::elem{'ID'}" eq $1) {
		$AFT_OUTPUT::pragma_postvar{$2} = $3;
	    } else {
		set_prevar($2,$3) if ($1 !~ /^-/);
	    }
	    return 1;
	};
	
	# See if we need to adjust tabstop.
	# #---TABSTOP=N
	#
	$1 =~ /TABSTOP=(\d+)/ and do {
	    $tabstop = $1;
	    print (STDERR "\n[$fname($lcnt):". 
		   " TABSTOP set to $tabstop spaces.]\n");
	    return 1;
	};
	
	output($AFT_OUTPUT::elem{'CommentLine'}."\n",line => $1);
	return 1;			# regular comment
    };
    
    return 0;			# no comments encountered
}

# Handle *Title, *Author and preamble output.
#
sub handle_title_preamble {
    my $fname = shift; my $lcnt = shift; local($_) = @_;
    
    # *Title:
    #
    /^\*Title:\s*(.*)$/ and do {
	$title = filter($1);
	return 1;
    };

    # *Author:
    #
    /^\*Author:\s*(.*)$/ and do {
	$author = filter($1);
	return 1;
    };


    # Output the preamble if we have been holding on to it.
    #
    if ($holding_preamble) {
	return 1 if /^\s*$/;		# empty line
	$holding_preamble = 0;
	output_preamble();

	# Now print out title and author if they were collected.
	# If *Title and *Author were the first two lines in the document,
	# then we held the preamble until they were collected.
	# Else we assume that they are not available, so we just print
	# the preamble.
	output($AFT_OUTPUT::elem{"Title"}."\n", title => $title) if $title;
	output($AFT_OUTPUT::elem{"Author"}."\n", author => $author) if $author;
    }
    return 0;			
}


#  Handle *Insert:, *Include:, *File:,*See File and table of contents.
#
sub handle_includes {
    my $fname = shift; my $lcnt = shift; local($_) = @_;
    
    /^\*(Insert|See File|Include|File):\s*(\S+)/ and do {
	process_file($2);
	return 1;
    };

    # *TOC:  (table of contents)
    #
    /^\*(TOC)/ and do {
	# If there is no automatic table of contents markup, then generate
	# an AFT style markup.
	if ($AFT_OUTPUT::elem{$1} eq '') {
	    generate_t_oC($fname);
	} else {
	    output($AFT_OUTPUT::elem{$1}."\n");
	}
	return 1;
    };
    return 0;
}

# Handle *Image: and it's variations.
#
sub handle_image {
    my $fname = shift; my $lcnt = shift; local($_) = @_;
    
    /^\*(Image|Image-left|Image-center|Image-right):\s*(\S+)/ and do {
	output($AFT_OUTPUT::elem{$1}."\n", image =>$2);
	return 1;
    };
    return 0;
}

# Handle ------
#
sub handle_ruler {
    my $fname = shift; my $lcnt = shift; local($_) = @_;
    
    /^\-{4,}/ and do {
	output($AFT_OUTPUT::elem{'HorizontalLine'}."\n");
	return 1;
    };
    
    return 0;
}

# Handle *, **, ***, ****, **** etc (sections) and
# ^*, ^**, ^***, ^**** (sections referencing TOC)
#
sub handle_sections {
    my $fname = shift; my $lcnt = shift; local($_) = @_;
    
    /^(\^*\*{1,7})\s*(.+?)\s*$/ and do {
	my($sname) = $2;
	if ($mode->{in_sect} eq 0) {
	    output($AFT_OUTPUT::elem{'BeginSectLevel1'}."\n");
	    $mode->{in_sect} = 1;
	}
	enter_section(length $1);

	$section_number->incr(length $1);
	my $number = $section_number->dotted();
	my $full_sname = $sname;
	$full_sname = "$number. $sname" if $autonumber;
	
	print (STDERR "]\n[$full_sname ") if $verbose;
	
	# print section name
	#
	output($AFT_OUTPUT::elem{$1}."\n", section => $sname, 
		text => filter($full_sname), number => $number);
	
	# Save the section for the TOC file.
	#
	if (length($1) < 5) {
	  my($level) = $1;
	  $level =~ tr/*^/\t/d;
	
	  print ($tocout "$level"."* {-$full_sname\@$sname-}\n") if $tocout;
	}
	return 1;
    };
    return 0;
}

# List Mode
#
sub handle_lists {
    my $fname = shift; my $lcnt = shift; local($_) = @_;
    
    # Only do this if not in verbatim/quote mode and we parse one of the 
    # following:
    #	<tab>*
    #	<tab>[text]
    #	<tab>number.
    #	<tab>number)
    #     <tab>#)
    #     <tab>#.
    #
    (!$mode->{in_verb} and !$mode->{in_quote} and 
     (/^(\t{1,})(\*|\[.+\]|\#[.\)]|\d+[.\)])(.*)$/)) and do {
	 my $rest_of_line = $3;
	 my $list = '';
	 my ($le, $name);
	 my $new_level = length($1);
	 my $cur_list_level = scalar @list_stack;
	 my $current_list = '';
	 
	 if ($cur_list_level gt 0) {
	     $current_list = $list_stack[$#list_stack];
	 }
	 
	 if ($2 =~ /^\*/) {
	     $list = 'Bullet';
	     $le = prepare_output($AFT_OUTPUT::elem{'BulletListElement'});
	 } elsif ($2 =~ /^\[(.+)\]/) {
	     $name = $1,
	     $list = 'Named',
	     $le = prepare_output($AFT_OUTPUT::elem{'NamedListElement'}, 
				  name => filter($name));
	 } else {
	     $list = 'Numbered';
	     $le = prepare_output($AFT_OUTPUT::elem{'NumberedListElement'});
	 }
	 # Are we nesting yet?
	 #
	 while ($cur_list_level < $new_level) {
	     # Increase nest level
	     #
	     push(@list_stack,$list);
	     end_list_element();
	     output($AFT_OUTPUT::elem{'Start'.$list.'List'}."\n");
	     
	     $cur_list_level++;
	     $current_list = $list;
	 } 
	 while ($cur_list_level > $new_level) {
	     # Retreat to a previous level
	     #
	     end_list_element();
	     $current_list = pop(@list_stack);
	     
	     output($AFT_OUTPUT::elem{'End'.$current_list.'List'}."\n");
	     
	     $cur_list_level--;
	     $current_list = pop(@list_stack);
	     push(@list_stack, $current_list);
	 }
	 if ($list ne $current_list) {
	     # Changing horses... A new list type.
	     #
	     end_list_element();
	     $current_list = pop(@list_stack);
	     
	     output($AFT_OUTPUT::elem{'End'.$current_list.'List'}."\n");
	     push(@list_stack,$list);
	     $current_list = $list;
	     output($AFT_OUTPUT::elem{'Start'.$list.'List'}."\n");
	 }
	 end_list_element();
	 
	 $mode->{in_list_el} = 1;
	 output($le);		# output element line
	 output(filter($rest_of_line));
	 return 1;
     };
    
    # Print a continuation of list element if in list mode and tabbed...
    #
    if (scalar(@list_stack) and /^\t\s*(.*)$/) {
	output(' '.filter($1));
	return 1;
    }

  end_list_element();
  return 0;
}

# Terminate list element.
#
sub end_list_element {
    if ($mode->{in_list_el}) {
	output($AFT_OUTPUT::elem{'End'.$list_stack[$#list_stack].
				      'ListElement'}."\n");
	$mode->{in_list_el} = 0;
    }
}

# Handle centered text.
#
sub handle_centered_text {
    my $fname = shift; my $lcnt = shift; local($_) = @_;
    
    (!scalar(@list_stack) and !$mode->{in_verb} and 
     !$mode->{in_quote} and /^\t{2,}(.*)$/) and do {
	 reset_states();	
	 output($AFT_OUTPUT::elem{'Center'}."\n", center => filter($1));
	 return 1;
     };
    
    return 0;
}

# Handle quoted text.
#
sub handle_quoted_text {
    my $fname = shift; my $lcnt = shift; local($_) = @_;
    
    (!$mode->{in_verb} and /^\t\#\s*(.*)$/) and do {
	if (!$mode->{in_quote}) { # if we aren't in quote mode yet...
	    reset_states();
	    output($AFT_OUTPUT::elem{'StartQuote'}."\n");
	    $mode->{in_quote} = 1;
	}
	output(filter($1)."\n");
	return 1;
    };
    return 0;
}

# Handle tables
#
sub handle_table {
    my $fname = shift; my $lcnt = shift; local($_) = @_;

    if ($AFT_OUTPUT::pragma_ctl{tableparser} eq 'new') {
	return handle_new_table_parser($fname, $lcnt, $_);
    }
    # If not in verbatim or quote mode, try table...
    #
    (!$mode->{in_verb} and !$mode->{in_quote} and /^\t\!(.*)$/)  and do {
	my $ecnt;			# Number of elements.
	my @elements;
	my $ftype;
	
	# First thing is first... Are we in the table yet?
	#
	!$mode->{in_table} and do {
	    reset_states();		# start clean
	    $mode->{in_table} = 1;
	    
	    # Don't really start the table yet. We need to know how many
	    # columns we will be dealing with.  Expect table headers next
	    # time through.
	    #
	    $mode->{need_table_headers} = 1;
	    $1 =~ /([^\!]*)/;
	    # The first thing we got was a caption. Save it for later.
	    #
	    $table_caption = filter($1);
	    return 1;
	};

	# Separator line !--------!
	#
	if ($1 =~ /[\-]+!$/) {
	    return 1;
	}
	# We should be in Table mode now. The first thing we should do
	# is split up columns into individual elements. Ignore bogus
	# trailing column. If we got less than 2 elements, this ain't no
	# table!
	#
	if (($ecnt = (@elements = split ("!", $1, 100)) - 1) < 2) {
	    print(STDERR 
		   "\n$fname($lcnt): Weirdness in a table... not enough columns.\n");
	    return 1;
	}
	
	# Okay, if this is the 2nd time through then we are looking for
	# table headers...
	#
	if ($mode->{need_table_headers}) {
	    # We got the column count ($ecnt) above, so we assume that
	    # it will stay consistent. If not, that's someone else's
	    # problem.
	    #
	    
	    output($AFT_OUTPUT::elem{'StartTable'}."\n", columns =>$ecnt,
		   caption => $table_caption);
	    output($AFT_OUTPUT::elem{'TableCaption'}."\n", 
		    caption => $table_caption);
	    $mode->{need_table_headers} = 0;	# don't need them anymore
	    $ftype = $AFT_OUTPUT::elem{'TableHeader'}; # short hand 
	} else {
	    $ftype = $AFT_OUTPUT::elem{'TableElement'}; # short hand
	}
	
	output($AFT_OUTPUT::elem{'TableRowStart'});
	# Now loop through each column element and spit it out.
	#
	foreach my $item (@elements) {
	    output($ftype, stuff => filter($item)) if $item;
	}
	
	# End of Table Row
	#
	output($AFT_OUTPUT::elem{'TableRowEnd'}."\n");
	return 1;
    };
    return 0;
}
    
# Handle ''New Style'' tables
#
my @row_acc;
sub handle_new_table_parser {
    my $fname = shift; my $lcnt = shift; local($_) = @_;
    
    # If not in verbatim or quote mode, try table...
    #
    (!$mode->{in_verb} and !$mode->{in_quote} and /^\t\!(.*)$/)  and do {
	my $ecnt = 0;			# Number of elements.
	my @elements;
	my $etype;
	
	my $tline = $1;

	# Protect \!
	$tline =~ s/\\!/%bang%/g;

	# First thing is first... Are we in the table yet?
	#
	!$mode->{in_table} and do {
	    reset_states();		# start clean
	    $mode->{in_table} = 1;
	    
	    # Don't really start the table yet. We need to know how many
	    # columns we will be dealing with.  Expect table headers next
	    # time through.
	    #
	    $mode->{need_table_headers} = 1;
	    if ($tline =~ /([^\!]*)/) { $tline = $1; }
#	    if ($1 =~ /([^\!]*)/) { $tline = $1; }
	    # The first thing we got was a caption. Save it for later.
	    #
	    $table_caption = filter($tline);
	    $mode->{eatOne} = 1;
	    return 1;
	};
	if ($tline =~ /[\-]+!$/ and $mode->{eatOne}) {
	  $mode->{eatOne} = 0;
	  return 1;
	}

	# Separator line !--------! means kick out previously accumulated row.
	#
	if ($tline =~ /[\-]+!$/) {
	    output($AFT_OUTPUT::elem{'TableRowStart'});
	    if ($mode->{need_table_headers}) {
		$etype = $AFT_OUTPUT::elem{'TableHeader'}; # short hand 
	    } else {
		$etype = $AFT_OUTPUT::elem{'TableElement'}; # short hand
	    }
	    if (@row_acc) {
		$mode->{need_table_headers} = 0 if $mode->{need_table_headers};
		while (my $item = pop(@row_acc)) {
		    output($etype, stuff => filter($item)) if $item;
		    if (scalar(@row_acc) > 2) {
			output($AFT_OUTPUT::elem{'TableElementSep'});
		    }
		}
		output($AFT_OUTPUT::elem{'TableRowEnd'}."\n");
	    }
	    return 1;
	}

	# otherwise...
	# We should be in Table mode now. The first thing we should do
	# is split up columns into individual elements. Ignore bogus
	# trailing column. If we got less than 2 elements, this ain't no
	# table!
	#

	if (($ecnt = (@elements = split ("!", $tline, 100)) - 1) < 2) {
	    print(STDERR 
		   "\n$fname($lcnt): Weirdness in a table... not enough columns.\n");
	    return 1;
	}

	# Okay, if this is the 2nd time through then we are looking for
	# table headers...
	#
	if ($mode->{need_table_headers}) {
	    # We got the column count ($ecnt) above, so we assume that
	    # it will stay consistent. If not, that's someone else's
	    # problem.
	    #
	    output($AFT_OUTPUT::elem{'StartTable'}."\n", columns =>$ecnt, 
		    caption => $table_caption);
	    output($AFT_OUTPUT::elem{'TableCaption'}."\n", 
		    caption => $table_caption);
	}

	# If just accumulating...
	# Now loop through each column element and save it.
	#
	my $col = @elements;
	foreach my $item (@elements) {
	    $row_acc[$col] .= $item if $item;
	    $col--;
	}
	return 1;
    };
    return 0;
}
    
    
# Handle verbatim issues.
#
sub handle_blocked_verbatim {
    my $fname = shift; my $lcnt = shift; local($_) = @_;
    if ($mode->{in_blocked_verb} or $mode->{in_filtered_verb}) {
	handle_verbatim($fname,$lcnt,$_);
	return 1;
    }
    return  0;			# drop thru
}

sub handle_verbatim {
    my $fname = shift; my $lcnt = shift; local($_) = @_;
    
    # Check to see if we should get out of blocked/filtered verbatim mode.
    #
    /^\^>>/ and do {
	# Get out of blocked and filtered verbatim mode
	reset_states();
	return 1;
    };
    
    # Verbatim Text (and yes, even Quoted Text continuations)
    #
    (/(^\t|^\^\<\<\w*)/ or 
     $mode->{in_blocked_verb} or $mode->{in_filtered_verb}) and do {
	 # First, are we starting fresh?
	 #
	 (!$mode->{in_verb} and !$mode->{in_quote}) and do {
	     reset_states();		# start clean
	     $mode->{in_verb} = 1;

	     # We are just entering the blocked verbatim mode, 
	     # so just remember this and don't print this line.
	     #
	     if ($1 =~ /\^\<\</) {
		 if ($POSTMATCH =~ /[Ff]/) {
		     $mode->{in_filtered_verb} = 1;
		     output($AFT_OUTPUT::elem{'StartFilteredVerbatim'}."\n");
		 } else {
		     $mode->{in_blocked_verb} = 1;
		     output($AFT_OUTPUT::elem{'StartBlockedVerbatim'}."\n");
		 }
		 return 1;
	     }			# else
	     output($AFT_OUTPUT::elem{'StartVerbatim'}."\n");
	 };
	 
	 # In quote mode? Just kick out filtered text.
	 #
	 output(filter($POSTMATCH)."\n"), return 1 if $mode->{in_quote};
	 
	 # We must be in a verbatim mode...
	 #
	 
	 # Kill the first tab
	 #
	 s/^\t//g if (!($mode->{in_blocked_verb} or $mode->{in_filtered_verb}));
	 
	 # Now change all tabs to 8 spaces.
	 #
	 s/\t/        /g if (!$mode->{in_blocked_verb});
	 
	 # Can we really filter FilterVerbatim?
	 #
	 if ($mode->{in_filtered_verb} and 
	     ($AFT_OUTPUT::elem{'FullFilterFilteredVerbatim?'} =~ /[Yy]/)) {
	     output(filter($_)."\n");
	 } else {
	     if ($AFT_OUTPUT::elem{'PreFilterVerbatim?'} =~ /[Yy]/) {
		 output(AFT_OUTPUT::prefilter($_)."\n");
	     } else {
		 output($_."\n");	# output 'as is'
	     }
	 }
	 return 1;
     };
    
    return 0;
}


# Generate and possibly include a table of contents file.
#
sub generate_t_oC {
    # Try and open a table of contents file
    #
    my ($fname) = @_;
    my $tocfile = $fname."-TOC";
    print (STDERR "\t Looking for a table of contents file...\n") if $verbose;
    
    open(TOCIN, $tocfile) and do {
	# Read it in.
	#
	print (STDERR "\t Reading table of contents from $tocfile...")if $verbose;
	process_FH_file(*TOCIN, $tocfile);
	close(TOCIN);
	output("\n\n");
	print (STDERR "Done.\n") if $verbose;
    };
    if ($verbose) {
	print (STDERR "\t Generating a new $tocfile.\n");
	print (STDERR "\t You may want to re-run aft again to include it if\n");
	print (STDERR "\t any sections were added or removed in your document.\n");
    }
    open(TOCOUT,">$tocfile");
    $tocout = *TOCOUT;
    print (TOCOUT "C--- AFT Table of Contents (auto generated)\n");
}


# filter(line) - processes line against macros and filters, returns filtered
# 	line.
#
sub filter {
    my($line) = @_;
    
    # Expand any prefilter pragma symbols.
    #
    #
    foreach my $key (keys(%pragma_prevar)) {
	my $val = $pragma_prevar{$key};
	$line =~ s/\%$key\%/$val/g;
    }
    
    # Now do the prefilters substitutions.
    #
    if ($AFT_OUTPUT::pragma_ctl{prefilter} eq 'yes') {
	$line =  AFT_OUTPUT::prefilter($line);
	
	# First, protect ||, \|,  __, \_,  \\, ~~ and \~ 
	# 
	$line =~ s/__|\\_/%UnDeRLiNE%/g;
	$line =~ s/\|\||\\\|/%PiPe%/g;
	$line =~ s/\~\~|\\\~/%TiLdE%/g;
	$line =~ s/''''/%QuOtE%/g;
	
	# Now, do the line-oriented face changes.
	#
	while ($line =~ s/(~|_|\||'')(.+?)(\1)/$AFT_OUTPUT::elem{"Start$face->{$1}"}$2$AFT_OUTPUT::elem{"End$face->{$1}"}/g) { }
	
	# Next, see if there any ''paragraph'' oriented face changes.
	#

	# Start of line markup
	#
	$line =~ /^(~|_|\||'').+$/ and do {
	    my $fc = $1;
	    my $fcn = $face->{$fc};
	    $paragraph->{lc($fcn)} = 1;
	    $line =~ s/^$fc/$AFT_OUTPUT::elem{"Start$fcn"}/;
	};
	
	# End of line markup
	#
	($line =~ /(~|_|\||'')$/ and $paragraph->{lc($face->{$1})}) and do {
	    my $fc = $1;
	    my $fcn = $face->{$fc};
	    $paragraph->{lc($fcn)} = 0;
	    $line =~ s/$fc$/$AFT_OUTPUT::elem{"End$fcn"}/;
	};
	
	# Now fix _ ~, \  and |
	# 
	$line =~ s/%UnDeRLiNE%/_/g;
	$line =~ s/%PiPe%/\|/g;
	$line =~ s/%TiLdE%/\~/g;
	$line =~ s/%QuOtE%/''/g;
	
    }

    # Handle footnote references
    #
    $line = handle_notes($line);

    # Handle index references
    #
    $line = handle_indexing($line);

    # Handle hyper links
    #
    $line = handle_links($line);
    
    
    # Post-filter now. Pass its return up to the caller of filter().
    #
    AFT_OUTPUT::postfilter($line) if ($AFT_OUTPUT::pragma_ctl{postfilter} eq 'yes');
}

sub handle_indexing {
    my($line) = @_;
    my $_cnt;

    if ($mode->{processing_input} == 0) { return $line; }
    if ($AFT_OUTPUT::pragma_ctl{verbatimsquarebrackets} eq 'yes') {
	return $line;
    }

	
    # Look for new explicitely called out indexes:
    # =[^indexed]= - Generate a unique target (by appending array length).
    #
    $line =~ s/=\[\^([^\]]+?)\]=/
	  $_cnt=@{$index{$1}},
	  push(@{$index{$1}},"$1$_cnt"),
	    prepare_output($AFT_OUTPUT::elem{'Index'},
                            text => "$1",
			    target => "$1$_cnt")/eg;
	return $line;
}

sub handle_notes {
    my($line) = @_;

    my $notenum = scalar(@note)+1;
    # look for (and replace) [Note: .. ]
    #
    $line =~ s/\[Note:\s*(.*)\]/
	handle_links("=[(REFiNtErNaLNOTE".$notenum.")]=").
	prepare_output($AFT_OUTPUT::elem{'Note'}, 
		       note => "$1",
		       notereftxt => $notenum,
		       notetarget => "iNtErNaLNOTE$notenum")/eg
		       and push(@note, $1); # save note
    return $line;
}

# Handle the various types of links we can regex.
#
sub handle_links {
    my($line) = @_;
    
    if ($AFT_OUTPUT::pragma_ctl{verbatimsquarebrackets} eq 'no') {
	# =[(target)]=
	#
	$line =~ s/=\[\(([^\[]+?)\)\]=/
	    prepare_output($AFT_OUTPUT::elem{'Target'},
			   target => "$1", 
			   text => $AFT_OUTPUT::elem{'NBSPACE'})/eg;
	
	# =[target]=
	#
	$line =~ s/=\[([^\]]+?)\]=/
	    prepare_output($AFT_OUTPUT::elem{'Target'},
			    target => "$1", text => "$1")/eg;

				 
	
	# new [name (url:reference)] style
	#
	$line =~ s/([^\\]|^)\[([^\[]+?)\s*\(((http?|file|ftp|mailto):.+?)\)\]/
	    $1.prepare_output($AFT_OUTPUT::elem{'URL'},
			      target => "$3", text => "$2", _text=>"$2")/eg;
	
	# new [name (:reference)] style (don't capture the : )
	#
	$line =~ s/([^\\]|^)\[([^\[]+?)\s*\(:(.+?)\)\]/
	    $1.prepare_output($AFT_OUTPUT::elem{'URL'},
			      target => "$3", text => "$2", _text=>"$2")/eg;
	
	# new [name (reference)] style
	#
	$line =~ s/([^\\]|^)\[([^\[]+?)\s*\((.+?)\)\]/
	    $1.prepare_output($AFT_OUTPUT::elem{'InternalReference'},
			      target => "$3", text => "$2")/eg;
	
	# new [reference] style
	#
	$line =~ s/([^\\]|^)\[([^\[]+?)\]/
	    $1.prepare_output($AFT_OUTPUT::elem{'InternalReference'},
			      target => "$2", text => "$2")/eg;
	
	$line =~ s/\\\[/"\["/eg;
    }
    BEGIN {
	# Construct the rather complex regex for simple http addresses.
	# We use a BEGIN block because we only want to do it once.
	my $_safe = q/$\-_@.&+~/;
	my $_extra = q/#!*,/;
	my $_alpha = q/A-Za-z/;
	my $_digit = q/0-9/;
	my $_esc = q/%/;
	my $_seg = "[$_alpha$_digit$_safe$_extra$_esc]+";
	my $_path = "(?:/$_seg)+";
	my $_params = "$_seg";
	my $_name = "[$_alpha$_digit][$_alpha$_digit\-]+";
	my $_hostname = "$_name(?:\\.$_name)+";
	my $_port = ":[0-9]+";
	$AFT::httpaddr = "(?:ftp|file|https?)://$_hostname(?:$_port)?(?:$_path)?";
    }
    
    # Handle plain old URLs terminated by brackets, spaces, periods and 
    # generally any character not listed in $_seg
    #
    $line =~ s/(^|[\s\(])($AFT::httpaddr)/
	"$1".(prepare_output($AFT_OUTPUT::elem{'URL'},
			     target => "$2", text => "$2", 
			     _text=>"")."$3")/eg;
    
    
    # Handle old AFT style Links
    $line =~ s/{\+((http|https|file|ftp|mailto)\:[^{}]+)\+}/
	prepare_output($AFT_OUTPUT::elem{'URL'},target => "$1", text => "$1", 
		       _text=>"")/eg;
    
    $line =~ s/{\-([^\@{}]+)[\@]((http|https|file|ftp|mailto)\:[^{}]+)\-}/
	prepare_output($AFT_OUTPUT::elem{'URL'},target => "$2", text => "$1",
		       _text=>"$1")/eg;
    
    $line =~ s/\{\+\:([^{}]+)\+}/
	prepare_output($AFT_OUTPUT::elem{'URL'},target => "$1", text => "$1",
		       _text=>"")/eg;
    
    $line =~ s/{\-([^\@{}]+)[\@]\:([^{}]+)\-}/
	prepare_output($AFT_OUTPUT::elem{'URL'},target => "$2", text => "$1",
		       _text=>"$1")/eg;
    
    $line =~ s/\{\+([^{}]+)\+}/
	prepare_output($AFT_OUTPUT::elem{'InternalReference'},
		       target => "$1", text => "$1")/eg;
    
    $line =~ s/{\-([^\@{}]+)\-}/
	prepare_output($AFT_OUTPUT::elem{'InternalReference'},
		       target => "$1", text => "$1")/eg;
    
    $line =~ s/{\-([^\@{}]+)[\@]([^{}]+)\-}/
	prepare_output($AFT_OUTPUT::elem{'InternalReference'},
		       target => "$2", text => "$1")/eg;
    
    $line =~ s/\}\+([^{}]+)\+\{/
	prepare_output($AFT_OUTPUT::elem{'Target'},
		       target => "$1", text => "$1")/eg;
    
    $line =~ s/\}\-([^{}]+)\-\{/
	prepare_output($AFT_OUTPUT::elem{'Target'},
		       target => "$1", text =>$AFT_OUTPUT::elem{'NBSPACE'})/eg;
    
    return $line;
}

# enterParagraph () - enter paragraph mode.
#
sub enter_paragraph {
    $mode->{in_para} = 1;
    output($AFT_OUTPUT::elem{'StartParagraph'}."\n");
}

# resetParagraph () - reset paragraph mode.
#
sub reset_paragraph {
    print (STDERR ".") if $verbose;
    output($AFT_OUTPUT::elem{'EndSmall'}."\n") if $paragraph->{small};
    output($AFT_OUTPUT::elem{'EndStrong'}."\n") if $paragraph->{strong};
    output($AFT_OUTPUT::elem{'EndEmphasis'}."\n") if $paragraph->{emphasis};
    output($AFT_OUTPUT::elem{'EndTeletype'}."\n") if $paragraph->{teletype};
    output($AFT_OUTPUT::elem{'EndParagraph'}."\n") if $mode->{in_para};
    $paragraph->{small} = 0;
    $paragraph->{strong} = 0;
    $paragraph->{emphasis} = 0;
    $paragraph->{teletype} = 0;
    $mode->{in_para} = 0;
}

# enterSection(level) - If we are nesting into a subsection, just keep track.
# Otherwise, unwind the stack of sections (outputing EndSection for each).
# Why keep a stack instead of a running level index? Unwinding can get tricky
# if the user does something like:
#  * Section
#  *** Section
#  ** Section 
#  **** Section
#  * Section
#
sub enter_section {
    
    BEGIN {
	# These keys are new. Don't choke if they don't exist. Don't
	# whine yet, just ignore them for now.
	#
	foreach my $name (qw(BeginSectLevel1 BeginSectLevel2 BeginSectLevel3
			     BeginSectLevel4
			     EndSectLevel1 EndSectLevel2 EndSectLevel3
			     EndSectLevel4)) {
	    if (!defined($AFT_OUTPUT::elem{$name})) {
		$AFT_OUTPUT::elem{$name} = "";
	    }
	}
    }
    
    my ($newsectlevel) = @_;
    reset_paragraph();
    
    # Do the section and section "level" mode popping...
    #
    if ($mode->{cur_sect_level} ge $newsectlevel) {
	while (@section_stack gt 0 and $section_stack[-1] ge $newsectlevel) {
	    $mode->{cur_sect_level} = pop(@section_stack);
	    output($AFT_OUTPUT::elem{'EndSect'.$mode->{cur_sect_level}}."\n");
	    if ($mode->{cur_sect_level} gt 3 and $newsectlevel le 3) {
		output($AFT_OUTPUT::elem{'EndSectLevel4'}."\n");
	    } elsif ($mode->{cur_sect_level} gt 2 and $newsectlevel le 2) {
		output($AFT_OUTPUT::elem{'EndSectLevel3'}."\n");
	    } elsif ($mode->{cur_sect_level} gt 1 and $newsectlevel le 1) {
		output($AFT_OUTPUT::elem{'EndSectLevel2'}."\n");
	    }
	}
    }
    
    # Do the section and section "level" pushing...
    #
    if (($mode->{cur_sect_level} le 3) and ($newsectlevel gt 3)) {
	output($AFT_OUTPUT::elem{'BeginSectLevel4'}."\n");
    } elsif (($mode->{cur_sect_level} le 2) and ($newsectlevel gt 2)) {
	output($AFT_OUTPUT::elem{'BeginSectLevel3'}."\n");
    } elsif (($mode->{cur_sect_level} le 1) and ($newsectlevel gt 1)) {
	output($AFT_OUTPUT::elem{'BeginSectLevel2'}."\n");
    }
    $mode->{cur_sect_level} = $newsectlevel;
    push(@section_stack, $newsectlevel);
}

# resetStates () - reset our state to near-normal (paragraph mode is not
# 	affected by this subroutine).
#
sub reset_states {
    # Are we in the middle of a table?
    #
    $mode->{in_table} and (!$mode->{need_table_headers} and 
			 output($AFT_OUTPUT::elem{'EndTable'}."\n"));
    
    # Since we can only be in one mode at a time, make like a big switch...
    #
  MODE: {
      output($AFT_OUTPUT::elem{'EndBlockedVerbatim'}."\n"), last MODE
	  if $mode->{in_blocked_verb};
      output($AFT_OUTPUT::elem{'EndFilteredVerbatim'}."\n"), last MODE
	  if $mode->{in_filtered_verb};
      output($AFT_OUTPUT::elem{'EndVerbatim'}."\n"), last MODE
	  if $mode->{in_verb};
      output($AFT_OUTPUT::elem{'EndQuote'}."\n"), last MODE
	  if $mode->{in_quote};
      
      end_list_element();
      while (my $list = pop(@list_stack)) {
	  output($AFT_OUTPUT::elem{'End'.$list.'List'}."\n");
      }
  }
    # Now just reset all the variables.
    #
    $mode->{need_table_headers} = 0;
    $mode->{in_table}= 0;
    $mode->{in_quote} = 0;
    $mode->{in_verb} = 0;
    $mode->{in_blocked_verb} = 0;
    $mode->{in_filtered_verb} = 0;
}


sub set_prevar {
    my ($key,$value) = @_;
    $pragma_prevar{$key} = $value;
}

# Print out a line of text (possibly with substitutions).
#
# Usage:  output(text [, key => value]..);
#
# %key% is replaced by value everywhere in text.
#
sub output {
    $my_print->(prepare_output(@_));
}

# Prepare a line of text for output.
#
# Usage:  prepareOutput(text [, key => value]..);
#
# %key% is replaced by value everywhere in text.
#
sub prepare_output {
    my $str = shift;
    my ($var, $val);
    
    while (@_) {
	$var = shift;
	$val = shift;
	my $fvar = "AFT_OUTPUT::$var";
	if (defined(&{$fvar})){
	    $str =~ s/\%$var\%/$fvar->($val)/eg;
	} else {
	    $str =~ s/\%$var\%/$val/g;
	}
    }
    
    return $str if ($mode->{in_verb} and 
		    !$mode->{in_filtered_verb} and
		    $AFT_OUTPUT::pragma_ctl{expandinverbatim} eq 'no');
    
    # Expand the document defined pragma variables.
    #
    foreach my $key (keys(%AFT_OUTPUT::pragma_postvar)) {
	$val = $AFT_OUTPUT::pragma_postvar{$key};
	$str =~ s/\%$key\%/$val/g;
    }
    return $str;
}


# Numbered Heads Initializaton
#
BEGIN {
    package Autonum;
    
    # usage: 
    #
    #   $num = Autonum->new;
    #   foreach  (qw/ 1 2 2 3 3 1 2 3 1/ ) {
    #     $num->incr($_, '.');
    #     print $num->dotted() , ':', "\n";
    #   }
    
    sub new {
	my ($class) = @_;
	my $self = { stack => [] };
	return bless $self, $class;
    }
    
    # returns the counter for current $level
    sub incr {
	my ($self, $level) = @_;
	# truncate and reset child numbers
	splice @{$self->{stack}}, $level;
	# 0 index
	return ++$self->{stack}->[$level - 1];
    }
    
    sub dotted {
	my ($self, $dot) = @_;
	$dot ||= '.';		# optional
	#                 v--- in case we skip levels, put a 0 in the gap.
	return join($dot, map {$_ || '0'} @{$self->{stack}});  #  . $dot;
    }
    
    # just the numbers, no punc
    sub list {
	my $self = shift;
	#      v--- in case we skip levels, put a 0 in the gap.
	return map {$_ || '0'} @{$self->{stack}};
    }
}
return 1;
