#
# Makefile.am for AFT
# 2002/03/16 alane@geeksrus.net
#

SUFFIXES=.dat .pm

.dat.pm:
	@PERL@ compile.pl $<

aft2rtf-doc.rtf: aft2rtf-doc.aft
	@PERL@ aft.pl --type=rtf aft2rtf-doc.aft

aft-refman.html: aft-refman.aft
	@PERL@ aft.pl --type=bn-html aft-refman.aft
	@PERL@ aft.pl --type=bn-html aft-refman.aft

aft.pl: aft.in
	@PERL@  -p -e 's|use lib.*|use lib ".";|' aft.in >aft.pl
	chmod a+x aft.pl

Makefile: $(BUILT_SOURCES)

bin_SCRIPTS=aft

BUILT_SOURCES=\
	aft.pl \
	aft-dbarticle.pm \
	aft-bn-html.pm \
	aft-html.pm \
	aft-lout.pm \
	aft-loutbook.pm \
	aft-loutreport.pm \
	aft-rtf.pm \
	aft-tex.pm \
	aft-xhtml.pm

pkgdata_DATA=$(BUILT_SOURCES) AFT.pm
pkgdata_SCRIPTS=compile.pl postrtf.pl launch_ie.pl

DOCS=aft2rtf-doc.rtf aft-refman.html
TOCS=aft2rtf-doc.aft-TOC aft-refman.aft-TOC
MISCDOCS=aft.gif aft.jpg aft.eps ChangeLog.aft

docdir=$(datadir)/doc/@PACKAGE@
examplesdir=$(docdir)/examples
backendsdir=$(docdir)/backends

doc_DATA=$(DOCS) $(MISCDOCS)

examples_DATA=\
	aft.aft \
	aft-refman.aft \
	aft2rtf-doc.aft

backends_DATA=\
	aft-dbarticle.dat \
	aft-bn-html.dat \
	aft-html.dat \
	aft-lout.dat \
	aft-loutbook.dat \
	aft-loutreport.dat \
	aft-rtf.dat \
	aft-tex.dat \
	aft-xhtml.dat

MOSTLYCLEANFILES=$(DOCS) $(TOCS) $(BUILT_SOURCES)

EXTRA_DIST=\
	$(pkgdata_SCRIPTS) \
	$(MISCDOCS) \
	$(examples_DATA) \
	$(backends_DATA) \
	AFT.pm \
	LICENSE.txt \
	Makefile.cvs \
	install.pl \
	trip-1.aft \
	trip.aft

#EOF
