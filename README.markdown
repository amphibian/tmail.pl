Tmail is a Perl script written by [Leo Notenboom](http://ask-leo.com/) of [Puget Sound Software](http://pugetsoundsoftware.com/) in 2003, and released as freeware. It's been very useful to me over the years, and it looks like it's not available anymore, so I preserve it here for posterity.

##Original Description

Tmail, for "Template Mail", is a little Perl script written to take the place of the common cgi program cgiemail, which was identified as having some security issues.

Tmail is executed as the result of an HTML Form, and reads a specified text file as a template. Tokens specified in the template file between square brackets are replaced with the values of parameters by those names entered in the form. The results are then mailed via sendmail.

###Parameters (specified as hidden variables in the HTML form)

- `template=filename`: filename of template to process, relative to the perl script's execution environment. Required.
- `success=page`: page to redirect to on successfull completion. ../html/index.html if not specified.
- `failure=page`: page to display on failure. IF specified, the page is parsed on output to allow the specific error message to be inserted. If not specified, an extremely simple error page is generated.

The template file is just a text file to be fed to "sendmail -oi -t". Form variable are referenced in [brackets], with substitution as follows:

- `[plain]`: replaced with the value of the passed in parameter "plain". Error if no such param.
- `[@email]`: replaced with the value of the passed in parameter "email", which is pumped through some rudimentary email validity checking. Error if no such param, OR if the email address fails the validity check. (Note that since the error checking only has to happen once, you need only to use this once per variable. Subsequent instances can be `[email]`.)
- `[$VAR]`: replaced with the value of the server's environment variable "VAR". Silently ignored and removed if no such var.
- `[!prot]`: replaced with the value of the passed in parameter "prot". Error if no such param. Prot is "protected", meaning it is restricted in the type of data it may contain. Should it fail that restriction, an error is generated. Right now that restriction causes failures if the data contains a carriage return or line feed (newline) character. (Note that like "@", you really only need to use this once per variable.)
- `[#optional]`: replaced with the value of the passed in parameter "optional", or REMOVED if there is no such parameter.

Note: a line in the template consisting only of `[newmail]` is considered a message boundry. When encountered the lines before it are packaged as email and sent, and lines after it are the start of a new mail message, which is sent the next time `[newmail]` is encountered, or when the template file ends. Essentially this is a simple way for tmail.pl to be able to send multiple, different, emails at a single request.Recommendation is that the template files be kept in the cgibin directory or equivalent, or some other not-web-readable location.

*IMPORTANT:* if you place an unprotected field in your email header, you are at risk for spammer hijacking. The header of your email - that means everything up to the first blank line - should include only "@" email variables, and "!" protected variables. In general, it's recommended the only user- entered data you allow in the email header be an email address. Anything else should only be placed in the body of the email.

###Example

This is a quick form to test tmail.pl:

	<form method="post" action="/cgi-bin/tmail.pl">
	<input name="template" type="hidden" value="tmailtest.txt" />
	<input name="success" type="hidden" value="http://ask-leo.com" />
	
	Email: <input name="email" type="text" size="45" /> <br />
	Plain field: <input name="plain" type="text" size="45" /> <br />
	Protected: <input name="prot" type="text" size="45" /> <br />
	Optional:
	<input type="radio" name="opt" value="one" /> one
	<input type="radio" name="opt" value="two" />two <br />
	<input type="submit" value="submit" name="submit" />
	</form>

And this would be the template file tmailtest.txt:

	From: tmail-example@pugetsoundsoftware.com
	To: [@email]
	Bcc: youremail@yourdomain.com
	Subject: tmail.pl test
	
	Plain Field: [plain]
	Protected: [!prot]
	Optional: [#opt]
	Environment: [$HTTP_REFERER]

The net result after the files are all installed in their appropriate locations is that values entered on the form are replaced in the specified locations in the template, and the result is sent via email.

tmail is freeware. It's a server-side Perl script, so it assumes you have CGI capability and Perl on your web server.