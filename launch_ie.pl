use Win32;
use Win32::OLE;
use strict;
$Win32::OLE::Warn = 0;
my $IEbrowser = Win32::OLE->GetActiveObject('InternetExplorer.Application') 
    || Win32::OLE->new('InternetExplorer.Application'); 
$IEbrowser->{visible} = 1;
$IEbrowser->navigate("file:///".$ARGV[0]); 
