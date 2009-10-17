#!/usr/bin/perl
print "Content-Type: text/html\n\n";

# tmail.pl
# Template based email CGI script. Takes the passed template and
# fills in delimited fields from additional parameters recieved
# via either GET or POST
#
# Paramters:
#   template=filename   filename of template to process, relative
#                       to the perl script's execution environment.
#                       Required.
#   success=page        page to redirect to on successfull completion.
#                       index.html if not specified
#   failure=page        page to display on failure. IF specified, the
#                       page is parsed on output as described in the
#                       comments for DisplayParse. If not specified,
#                       an extremely simple error page is generated.
#
# Template format
#   Assumed to be a sequence of lines to be fed to "sendmail -oi -t".
#   Variable are referenced in [brackets], with substitution as
#   follows:
#
#       [plain]         replaced with the value of the passed in
#                       parameter "plain". Error if no such param.
#       [@email]        replaced with the value of the passed in
#                       parameter "email", which is pumped through
#                       some rudimentary email validity checking.
#                       Error if no such param, OR if the email
#                       address fails the validity check. (Note
#                       that you really only need to use this once
#                       per variable.)
#       [$VAR]          replaced with the value of the environment
#                       variable "VAR". Error if no such var.
#       [!prot]         replaced with the value of the passed in
#                       parameter "prot". Error if no such param.
#                       Prot is "protected", meaning it is restricted
#                       in the type of data it may contain. Should it
#                       fail that restriction, an error is generated.
#                       (Note that you really only need to use this
#                       once per variable.)
#       [#optional]     replaced with the value of the passed in
#                       parameter "optional", or REMOVED if there
#                       is no such parameter.
#
#   Note: a line consisting only of
#       [newmail]
#   is considered a boundry. When encountered the lines before it are
#   packaged as email and sent, and lines after it are the start of a
#   NEW mail message, which is sent the next time [newmail] is encountered,
#   or when the template file ends.
#
# Recommendation is that the template files be kept in the
# cgibin directory or equivalent, or some other not-web-readable
# location.
#
# History:
# 12-Oct-2003   LeoN    Created
# 18-Oct-2003   LeoN    Altered interpolation code to not attempt
#                       to parse passed-in data. Thus, square brackets
#                       may once again be (safely) used on forms.
# 19-Dec-2003   LeoN    Bugfix: missing use IO::File; which caused
#                       script to fail if "failure" parameter specified
#                       and used.
# 22-Dec-2003   LeoN    Added "[newmail]" template indicator, and the
#                       ability to send multiple peices of email.
# 15-Mar-2004   LeoN    Bugfix: referenced environment variables that are
#                       not defined are no longer fatal. Not only is this
#                       more consistant with environment variable usage
#                       elsewhere, but allows HTTP_REFERRER to be used
#                       in templates, since it's not always present.
#
# Copyright 2003 Puget Sound Software LLC
#
# By using this script you agree to assume all risk for its
# use. It may or may not meet your needs. It's extremely
# unlikely, but it might have bugs that could harm or delete
# files on your computer. Perhaps all of them. Puget Sound
# Software assumes no liability for any damage caused by your
# use of this script in any way.
#
# You may use and modify this script free of charge as long as
# you keep this copyright notice and the comments above.
#
use IO::File;

$szRedirect = "../html/index.html";
$szError = "";

# debug logging. Helpful to diagnose what's up. Will log
# both the input parameters, as well as the generated email
# script, to a file.
#
$fLog = 0;
open (LOG, ">tmail.log") if ($fLog);

# email addresses on these domains are considered invalid.
# Replace this list with your own.
#
@blacklist = (
                "pugetsoundsoftware\\.com",
                "ask-leo\\.com",
                );

# Unpack all arguments, GET and POST, & put 'em in a hash. Note that if
# a param is specified on both, the URL always wins.
#
if (defined ($ENV{'CONTENT_LENGTH'}))
    {
    read(STDIN, $buffer, $ENV{'CONTENT_LENGTH'});
    @pairs = split(/&/, $buffer);
    foreach $pair (@pairs)
        {
        ($name, $value) = split(/=/, $pair);
        $value =~ tr/+/ /;
        $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $PARAMS{$name} = $value;
        print LOG "POST: " . $name . "=[" . $value . "]\n" if ($fLog);
        }
    }
if (defined ($ENV{'QUERY_STRING'}))
    {
    $buffer = $ENV{'QUERY_STRING'};
    @pairs = split(/&/, $buffer);
    foreach $pair (@pairs)
        {
        ($name, $value) = split(/=/, $pair);
        $value =~ tr/+/ /;
        $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $PARAMS{$name} = $value;
        print LOG "GET: " . $name . "=[" . $value . "]\n" if ($fLog);
        }
    }

# grab the form we're to process
#
DisplayError ("tmail: template form not specified")
    if (!defined ($PARAMS{"template"}) || ("" eq $PARAMS{"template"}));
$szForm = $PARAMS{"template"};

# make sure it exists
#
DisplayError ("tmail: template form [$szForm] does not exist")
    if (! -e $szForm);

# Attempt to open the file
#
DisplayError ("tmail: template form [$szForm] could not be opened")
    if (!open ($file, "<$szForm"));

# loop line by line
#
$szMailBody = "";
while (<$file>)
    {
    $i = 100;
    $szLine = $_;
    $szLine =~ s/[\r\n]*$//;
    
    if ($szLine =~ /^\s*\[newmail\]\s*$/i)
        {
        # message separator. Send first mail, and start another.
        #
        if ($fLog)
            {
            print LOG $szMailBody;
            close (LOG);
            }
        Mail ($szMailBody);
        $szMailBody = "";
        }
    else
        {
        while ($szLine =~ /^(.*?)\[(.)(.*?)\](.*)$/)
            {
            # There are substitutions to be made. We've split into:
            #   $1 - line up to "["
            #   $2 - first char after "["
            #   $3 - rest of chars up to "]"
            #   $4 - rest of line after "]"
            #
            $szMailBody .= $1;

            if ("@" eq $2)
                {
                # email substitution
                DisplayError ("tmail: email parameter [$3] used but not defined")
                    if (! defined ($PARAMS{$3}));
                # validate email addresses somewhat
                valid_email($PARAMS{$3});
                $szMailBody .= $PARAMS{$3};
                }

            elsif ("\$" eq $2)
                {
                # environment substitution
                $szMailBody .= $ENV{$3};
                }

            elsif ("!" eq $2)
                {
                # plain substitution
                DisplayError ("tmail: protected parameter [$3] used but not defined")
                    if (! defined ($PARAMS{$3}));
                # validate protected parameter
                valid_param ($PARAMS{$3});
                $szMailBody .= $PARAMS{$3};
                }

            elsif ("#" eq $2)
                {
                # optional substitution. Remove if not defined.
                $szMailBody .= $PARAMS{$3}
                    if (defined ($PARAMS{$3}));
                }

            else
                {
                # plain substitution
                DisplayError ("tmail: paramter [$2$3] used but not defined")
                    if (! defined ($PARAMS{$2 . $3}));
                $szMailBody .= $PARAMS{$2 . $3};
                }
            $szLine = $4;
            }
        $szMailBody .= $szLine . "\n";
        }
    }
close ($file);

# Got this far ... ship it.
#
if ($fLog)
    {
    print LOG $szMailBody;
    close (LOG);
    }
Mail ($szMailBody);

# grab redirection page, if specified.
#
$szRedirect = $PARAMS{"success"} if (defined ($PARAMS{"success"}) && ("" ne $PARAMS{"success"}));
print "<HTML>\n<HEAD>\n<meta http-equiv=\"refresh\" content=0;url=\"$szRedirect\">\n</HEAD>\n</HTML>\n";

exit (0);

# DisplayError
# Display internal error message. Shouldn't ever happen in real life.
# (And we all know about "shouldn't").
#
sub DisplayError
    {
    if ("" ne $szError)
        {
        # already recursing on error. Display plain text.
        print "<HTML><HEAD><TITLE>Template Form Processor - Error</TITLE></HEAD>\n";
        print "<BODY><BR>[" . $szError . "]<BR></BODY></HTML>\n";
        }
    else
        {
        $szError = shift @_;
        return if (!defined ($szError) || ("" eq $szError));

        # recursion here forces plain page above if no page specified.
        DisplayError ($szError)
            if (!defined ($PARAMS{"failure"}) || ("" eq $PARAMS{"failure"}));

        # else display the error page specified
        my %subs;
        $subs{"error"} = $szError;
        DisplayParse ($PARAMS{"failure"}, %subs);
        }

    exit (1);
    }

# valid_email()
#
# This is a function that checks to see if an e-mail address that's
# passed into it is valid.  In order to be considered valid, it must have
# the following characteristics:
#
#      - @ sign must exist
#      - no spaces or other illegal characters
#      - one period to the right of @, and two characters after that
#      - one character to the left of @
#      - the domain can't be on a "blacklist", like thisistrue.com
#
# If there are any errors, they are returned as text strings, otherwise
# null is returned.
#
sub valid_email
    {
    $address = shift @_;

    DisplayError ("No email address supplied")
        if (!defined ($address) || ("" eq $address));

    # required characters
    DisplayError ("Invalid e-mail -- missing @ sign [$address]")
        if (!($address =~ /\@/));

    # Do we have a space?
    DisplayError ("There is a space in the e-mail address [$address]")
        if ($address =~ / /);

    # Do we have anything else that's not allowed?
    DisplayError ("Invalid character in e-mail address [$address]")
        if ($address =~ /[^A-Za-z0-9-_+\@\.]/);

    # Make sure we have period followed by at least 2 characters in the domain
    DisplayError ("Invalid domain name [$address]")
        if (!($address =~ /@.*\.../));

    # Check for a character to the left of @
    DisplayError ("Invalid e-mail address [$address]")
        if (!($address =~ /.@/));

    # Loop through our blacklist
    foreach $domain (@blacklist)
        {
        # Does this domain match?
        DisplayError ("Reserved domain name in e-mail address")
            if ($address =~ /\@$domain$/i);
        }
    }

# valid_param()
#
# This is a function that checks that the passed parameter contains only
# "valid" characters.
#
# Right now we simply disallow \r and \n.
#
sub valid_param
    {
    $param = shift @_;

    # Do we have anything that's not allowed?
    DisplayError ("Invalid character in parameter [$param]")
        if ($param =~ /[\r\n]/);
    }

# DisplayParse
# Read the referenced file, parsing it for some simple substitutions,
# and display it.
# First param is filename to read.
# Second is a hash, of token, value pairs
#
# Tokens in the incoming HTML must be of form:
#
#   <!-- [token] -->
#
# and must be on a single line. The entire line is then replaced
# with a line containing the value associated with the token.
#
# See also notes in script header regarding test site and other "on the
# fly" modifications we make to the file being displayed.
#
sub DisplayParse
    {
    $filename = shift @_;
    %subHash = (@_);
    my $file = new IO::File;

    # no filename to read? Internal error - shouldn't happen
    #
    DisplayError ("tmail: Internal Error: No File")
        if (!defined ($filename) || ("" eq $filename));

    # make sure it exists
    #
    DisplayError ("tmail: Internal Error: File [$filename] Does Not Exist")
        if (! -e $filename);

    # Attempt to open the file
    #
    DisplayError ("tmail: Internal Error: Can't open file")
        if (!open ($file, "<$filename"));

    # loop line by line
    #
    while (<$file>)
        {
        # process includes
        #
        DisplayParse ("../html/" . $1, %subHash)
            if (/^\s*<!--#include FILE="(.*)" -->\r*$/);

        # process HREFs
        #
        s@HREF=\"([\w\-\/]*\.)@HREF=\"../$1@gi;
        s@SRC=\"([\w\-\/]*\.)@SRC=\"../$1@gi;
        s@BACKGROUND=\"images([\w\-\/]*\.)@BACKGROUND=\"../images$1@gi;

        # Process token substitution
        #
        if (/^<!-- *\[(.*)\] *-->\r*$/)
            {
            # substitution
            #
            print $subHash{$1} . "\n";
            }
        else
            {
            print;
            }
        }
    }

# Mail
# Pump out message body via sendmail
#
sub Mail
    {
    my $sendmail = "/usr/sbin/sendmail";
    my $message = shift @_;

    open (TEST, ">/tmp/tmail.log");
    print TEST $message;
    close (TEST);

    # Check for sendmail
    DisplayError ("Unable to execute '$sendmail': $!")
        if (! -x $sendmail);

    # Try to open a pipe to sendmail
    DisplayError ("Unable to open a pipe to sendmail: $!")
        if (!open(MAIL, "| $sendmail -oi -t "));

    print MAIL $message;
    close(MAIL);
    }
