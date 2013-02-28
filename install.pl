: # use perl                                  -*- mode: Perl; -*-
	eval 'exec perl -S $0 "$@"'
		if $running_under_some_shell;

# Simple AFT Installer for DOS/Unix (version 3.1)
#

print <<E_PRE

		    Welcome to the AFT installer.

   I will ask you a few questions and try to make the installation
 as painless as possible.  At any time you can abort the installation
	      by typing 'quit' when prompted for input.

E_PRE
    ;


$_deftype="html";
$_aftdest="/usr/local/lib/aft";
$_aftexedest="/usr/local/bin";

if ("$ENV{'COMSPEC'}" ne '' && "$ENV{'OSTYPE'}" !~ 'cygwin') {
    print "  Looks like you are on an MS Windows machine...\n";
    $os="msdos";
    $_aftdest="c:/aft";
    $_aftexedest = ("$ENV{'COMSPEC'}" =~ /WINNT/) ? "C:/WINNT" : "C:/WINDOWS";
} else {
    die "Please follow the instructions in the file INSTALL.";
}

print "  Your Perl is version $].\n\n";
die "  Sorry, but you need at least version  5.001 to run aft!" if ($] < 5);

$perl5exe = $^X;

print <<INST

Okay, now you need to determine where the AFT files will live.

INST
    ;
GETLIBDIR: {
    $aftdest = prompt("Create AFT directory here?", $_aftdest);
    if (! -d $aftdest) {
      print "  $aftdest doesn't exist.  ";
      $yn = prompt("Should I create it?", "no");
      if ($yn =~ /no/) {
	print "  Try again.\n";
	goto GETLIBDIR;
      }
      mkdir $aftdest,0777;
    }
}

GETEXEDIR: {
    $aftexedest = prompt("Put AFT startup script here?", $_aftexedest);
    if (! -d $aftexedest) {
	print "  $aftexedest doesn't exist.  ";
	$yn = prompt("Should I create it?", "no");
	if ($yn =~ /no/) {
	    print "  Try again.\n";
	    goto GETEXEDIR;
	}
	mkdir $aftexedest,0777;
    }
}

$aftdatadest = $aftdest."/lib";
if (! -d $aftdatadest) {
    mkdir $aftdatadest,0777;
}

$aftdocdest = $aftdest."/doc";
if (! -d $aftdocdest) {
    mkdir $aftdocdest,0777;
}

if ($os eq "msdos") {
  $aftexe = "$aftexedest/aft.pl";
} else {
  $aftexe = "$aftexedest/aft";
}

print "\nInstalling aft libs into $aftdest and startup script into $aftexedest...\n";
open (AFT_IN, "<aft.in");
open (AFT_OUT, ">$aftexe");

while (<AFT_IN>) {
  s/use lib \"\@prefix\@\/share\/\@PACKAGE\@\"/use lib qw \($aftdatadest\)/;
    print AFT_OUT;
}
close(AFT_IN);
close(AFT_OUT);

if ($os ne "msdos") {
  chmod 0755,"$aftexedest/aft";
} else {
    open (AFT_IE, ">$aftdatadest/aft-htm.dat");
    print AFT_IE "use $aftdatadest/aft-bn-html.dat\n";
    print AFT_IE "PostProcessor\t".'exec "$^X @INC[0]/launch_ie.pl \"$outputfile\""'."\n";
    close (AFT_IE);
    
    $yn = prompt("Preview resulting .htm in IE after AFT runs?", "yes");
    open (AFT_BATOUT, ">$aftexedest/aft.bat");
    if ($yn =~ /y/) {
	$run_ie = 1;
	print AFT_BATOUT "$perl5exe $aftexe --type=htm --verbose \%1 \%2 \%3 \%4";
    } else {
	$run_ie = 0;
	print AFT_BATOUT "$perl5exe $aftexe --verbose \%1 \%2 \%3 \%4";
    }
    close(AFT_BATOUT);

    $yn = prompt("Try and associate all files ending with .aft with AFT?", "yes");
    if ($yn =~ /y/) {
	use Win32;
	use Win32::TieRegistry;
	$Registry->Delimiter("/");
	$Registry->{"HKEY_CURRENT_USER/Software/Microsoft/Windows/CurrentVersion/Explorer/FileExts/.aft/"} = {
	    "/Application" => "aft.bat",
	    "OpenWithList/" => {
		"/a" => "aft.bat",
		"/MRUList" => "a"
		}
	};
	print "\nNow you can double click on .aft files to run AFT.";
    }
    

}

print "\nInstalling support files into $aftdatadest...";
copyfile("AFT.pm", $aftdatadest);
copyfile("postrtf.pl", $aftdatadest);
copyfile("launch_ie.pl", $aftdatadest);
copyfile("compile.pl", $aftdatadest);
copyfile("aft-html.dat", $aftdatadest);
copyfile("aft-bn-html.dat", $aftdatadest);
copyfile("aft-lout.dat", $aftdatadest);
copyfile("aft-xhtml.dat", $aftdatadest);
copyfile("aft-rtf.dat", $aftdatadest);
copyfile("aft-tex.dat", $aftdatadest);

print "\nInstalling documentation files into $aftdatadest...";
copyfile("aft-refman.aft", $aftdocdest);
copyfile("aft2rtf-doc.aft", $aftdocdest);
copyfile("aft.gif", $aftdocdest);

print "\nCompiling rules...\n\t";
system "$perl5exe $aftdatadest/compile.pl $aftdatadest/aft-html.dat";
system "$perl5exe $aftdatadest/compile.pl $aftdatadest/aft-htm.dat";
system "$perl5exe $aftdatadest/compile.pl $aftdatadest/aft-lout.dat";
system "$perl5exe $aftdatadest/compile.pl $aftdatadest/aft-xhtml.dat";
system "$perl5exe $aftdatadest/compile.pl $aftdatadest/aft-tex.dat";
system "$perl5exe $aftdatadest/compile.pl $aftdatadest/aft-rtf.dat";
print "\nCreating documentation...";
print "\natf2rtf-doc.rtf..";
system "$perl5exe $aftexe --type=rtf  $aftdocdest/aft2rtf-doc.aft";
print "\natf-refman.html..";
system "$perl5exe $aftexe --type=html  $aftdocdest/aft-refman.aft";
if ($os eq "msdos" && $run_ie) {
    system "$perl5exe $aftexe --type=htm  $aftdocdest/aft-refman.aft";
} else {
    system "$perl5exe $aftexe --type=html  $aftdocdest/aft-refman.aft";
}
print "\nInstallation is complete!";
print "  Press Return to exit:";
$ans = <STDIN>;

sub prompt {
    local($text, $default) = @_;
    local($ans);
    printf ("%s [%s]: ", $text, $default);
    $ans = <STDIN>;
    if ($ans eq "\n") {
	$ans = $default;
    } else {
	chop $ans;
    }
    die "Aborting installation" if ($ans =~ /quit/);
    return $ans;
}

sub copyfile {
    local($fname,$dest) = @_;
    if ($os eq "msdos") {
	$dest =~ s/\//\\/g; # fix slashes
	$copy="copy";
    } else {
	$copy="cp";
    }
    `$copy $fname $dest`;
}
