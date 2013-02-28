#
# postrtf.pl - postprocessing of rtf-files generated from AFT
#
# Copyright (C) 2001 Eva Maria Krause.  All rights reserved.

# usage
(@ARGV == 0) && do {
    print (STDERR "Usage: postrtf filename.rtf \n");
    exit 2;
};

$rtffile = $ARGV[0] || die "postrtf: no rtffile specified\n";;

open(FILE, "<$rtffile") || die "postrtf: $rtffile couldn't be opened: $!\n";

while (<FILE>) { $STR .= $_; }
close (FILE);

# constants
$stdind = 500; # standard-indention in twips
$stdcolwidth = 1000; # standard-column-width of table columns

$verbrtf = "\\line\\li"; # rtf-verbatim-code

$listind = "\\par\\pard\\li"; # list-indention
$bul = "\{\\f2\\fs30\\bullet\}"; # bullet in bullet-lists

$celldesign = "\\clbrdrt\\brdrw15\\brdrs". # top border
              "\\clbrdrl\\brdrw15\\brdrs". # left border
              "\\clbrdrb\\brdrw15\\brdrs". # bottom border
              "\\clbrdrr\\brdrw15\\brdrs"; # right border

# for no borderlines, substitute by
# $celldesign = "";

##########################
# handle verbatim-blocks #
##########################
$STR=~s/\\verbatim/\\§verbatim/g;
$STR=~s/\n\\endverbatim/\\§endverbatim\n/g;

# special case: {+, {-, }+, }- in verbatim-block
while ($STR=~m/\\§verbatim([^§]*)[^\\]([\{\}][\+\-])/) {
      $STR=~s/\\§verbatim([^§]*)([^\\])([\{\}][\+\-])/\\§verbatim$1$2\\$3/g;
}
while ($STR=~m/\\§verbatim([^§]*)[\+\-]([\{\}])/) {
      $STR=~s/\\§verbatim([^§]*)([\+\-])([\{\}])/\\§verbatim$1$2\\$3/g;
}
# replace blanks in verbatim-block by \~
while ($STR=~m/\\§verbatim([^§]*) /) {
      $STR=~s/\\§verbatim([^§]*) /\\§verbatim$1\\~/g;
}
# indent each line in verbatim-block
while ($STR=~m/\\§verbatim([^§\n]*)\n/) {
      $STR=~s/\\§verbatim([^§\n]*)\n/$1\n$verbrtf$stdind \\§verbatim/g;
}

$STR=~s/\\§verbatim//g;
$STR=~s/\\§endverbatim/\\par\\pard/g;

############################
# handle list-environments #
############################
$STR=~s/\\(num|bul)list/\\§beginlist$1/g;
$STR=~s/\\end(num|bul)list/\\§endlist$1/g;

# assign level to each list, starting with 0
$level=0;
$countlevel=0;
while ($STR=~m/\\§beginlist/ || $STR=~m/\\§endlist/) {
      if ($STR=~m/\\bl[^§]*\\§endlist/) { # most inner list
        $level--;
        $STR=~s/\\bl([^§]*)\\§endlist/\\bl$1\\el$level/;
      } else {
        $STR=~s/\\§beginlist/\\bl$level$1/;
        $level++;
        if ($level>$countlevel) {$countlevel=$level;}
      }
}

# handle bullet-lists
$STR=~s/\\bl(\d*)bul/\\§bl$1/g;
$STR=~s/\\el(\d*)bul/\\§ebl$1/g;

$STR=~s/\\bulitem/%item%/g;

# new paragraph after the most outer list
$STR=~s/\\§ebl0/\\§ebl0\\par\\pard/g;

for ($ii=$countlevel-1; $ii>=0;$ii--) {
    $ind = ($ii+1)*$stdind;
    while ($STR=~m/\\§bl$ii([^§%]*)%item%/) {
          $STR=~s/\\§bl$ii([^§%]*)%item%/$1$listind$ind $bul\\§bl$ii/g;
    }
    $STR=~s/\\§bl$ii([^§]*)\\§ebl$ii/$1/g;
}

# handle numbered lists
$STR=~s/\\bl(\d*)num/\\§nl$1/g;
$STR=~s/\\el(\d*)num/\\§enl$1/g;

$STR=~s/\\numitem/%item%/g;

# new paragraph after the most outer list
$STR=~s/\\§enl0/\\§enl0\\par\\pard/g;

for ($ii=$countlevel-1; $ii>=0;$ii--) {
    $ind = ($ii+1)*$stdind;
    $nr=1;
    while ($STR=~m/\\§nl$ii([^§%]*)%item%/) {
          $STR=~s/\\§nl$ii([^§%]*)%item%/$1$listind$ind $nr.\\§nl$ii/g;
          $nr++;
    }
    $STR=~s/\\§nl$ii([^§]*)\\§enl$ii/$1/g;
}

# handle tables
$STR=~s/\\cellxx/\\§cellx/g;

while ($STR=~m/\\tabcols/) {
      $STR=~s/\\tabcols(\d*)\\endtabcols//;
      $count = $1; # number of columns

      for ($i = 1; $i <= $count; $i++) {
         $colwidth = $i*$stdcolwidth;
         $STR=~s/\\§cellx/\n$celldesign\\cellx$colwidth\\§cellx/;
      }
      $STR=~s/\\§cellx//;
}

# join lines with intermediate space if beginning with letters, numbers or left curly braces
$STR=~s/\n(\w|\{)/ $1/g;

# delete leading spaces
$STR=~s/\n /\n/g;

# eliminate multiple blank lines
$STR=~s/\n+/\n/g;

# eliminate multiple spaces
$STR=~s/ +/ /g;

# delete spaces in front of backslashes
$STR=~s/ \\/\\/g;

# delete spaces after left curly brace
$STR=~s/\{ /\{/g;

open(FILE, ">$rtffile") || die "postrtf: $rtffile couldn't be opened: $!\n";
print FILE $STR;
close (FILE);