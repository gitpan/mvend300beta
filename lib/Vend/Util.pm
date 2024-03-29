# $Id: Util.pm,v 1.9 1997/05/22 07:00:05 mike Exp $

package Vend::Util;
require Exporter;

# AUTOLOAD
#use AutoLoader;
#@ISA = qw(Exporter Autoloader);
#*AUTOLOAD = \&AutoLoader::AUTOLOAD;
# END AUTOLOAD

# NOAUTO
@ISA = qw(Exporter);
# END NOAUTO

@EXPORT = qw(

blank
currency
check_security
file_modification_time
format_log_msg
international_number
is_no
is_yes
generate_key
logtime
logData
logDebug
logError
logGlobal
lockfile
unlockfile
readfile
readin
random_string
quoted_string
quoted_comma_string
setup_escape_chars
escape_chars
send_mail
secure_vendUrl
tag_nitems
tag_item_quantity
tainted
trim_desc
uneval
vendUrl

);
@EXPORT_OK = qw(append_field_data append_to_file csv field_line);

use strict;
use Carp;
use Config;
use Fcntl;
use POSIX 'strftime';
use subs qw(logError logGlobal);
# We now use File::Lock for Solaris and SGI systems
#use File::Lock;

my $Uneval_routine;

### END CONFIGURABLE MODULES


## ESCAPE_CHARS

$ESCAPE_CHARS::ok_in_filename = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' .
    'abcdefghijklmnopqrstuvwxyz' .
    '0123456789' .
    '-_.$/';

sub setup_escape_chars {
    my($ok, $i, $a, $t);

    foreach $i (0..255) {
        $a = chr($i);
        if (index($ESCAPE_CHARS::ok_in_filename,$a) == -1) {
	    $t = '%' . sprintf( "%02X", $i );
        } else {
	    $t = $a;
        }
        $ESCAPE_CHARS::translate[$i] = $t;
    }
}

# Replace any characters that might not be safe in a filename (especially
# shell metacharacters) with the %HH notation.

sub escape_chars {
    my($in) = @_;
    my($c, $r);

    $r = '';
    foreach $c (split(//, $in)) {
	$r .= $ESCAPE_CHARS::translate[ord($c)];
    }

    # safe now
    $r =~ m/(.*)/;
    $r = $1;
    $r;
}

# Returns its arguments as a string of tab-separated fields.  Tabs in the
# argument values are converted to spaces.

sub tabbed {        
    return join("\t", map { $_ = '' unless defined $_;
                            s/\t/ /g;
                            $_;
                          } @_);
}

my(%Tab);

sub international_number {
    return $_[0] unless $Vend::Cfg->{Locale};
	unless (%Tab) {
		%Tab = (	',' => $Vend::Cfg->{Locale}->{mon_thousands_sep},
					'.' => $Vend::Cfg->{Locale}->{mon_decimal_point}  );
	}
    $_[0] =~ s/([^0-9])/$Tab{$1}/g;
	return $_[0];
}

sub commify {
    local($_) = shift;
    1 while s/^(-?\d+)(\d{3})/$1,$2/;
    return $_;
}

# Trims the description output for the order and search pages
# Trims from $Vend::Cfg->{'DescriptionTrim'} onward
sub trim_desc {
	return $_[0] unless $Vend::Cfg->{'DescriptionTrim'};
	my($desc) = @_;
	$desc =~ s/$Vend::Cfg->{'DescriptionTrim'}(.*)//;
	$desc;
}

# Finds common-log-style offset
# Unproven, authoratative code welcome
my $Offset;
FINDOFFSET: {
    my $now = time;
    my ($gm,$gh,$gd,$gy) = (gmtime($now))[1,2,5,7];
    my ($lm,$lh,$ld,$ly) = (localtime($now))[1,2,5,7];
    if($gy != $ly) {
        $gy < $ly ? $lh += 24 : $gh += 24;
    }
    elsif($gd != $ld) {
        $gd < $ld ? $lh += 24 : $gh += 24;
    }
    $gh *= 100;
    $lh *= 100;
    $gh += $gm;
    $lh += $lm;
    $Offset = sprintf("%05d", $lh - $gh);
    $Offset =~ s/0(\d\d\d\d)/+$1/;
}

# Returns time in HTTP common log format
sub logtime {
    return POSIX::strftime("[%d/%B/%Y:%H:%M:%S $Offset]", localtime());
}

sub format_log_msg {
	my($msg) = @_;
	my(@params);

	# IP, Session, REMOTE_USER (if any) and time
    push @params, ($CGI::host || '-');
	push @params, ($Vend::SessionName || '-');
	push @params, ($CGI::user || '-');
	push @params, logtime();

	# Catalog name
	my $string = ! defined $Vend::Cfg ? '-' : $Vend::Cfg->{CatalogName};
	push @params, $string;

	# Path info and script
	$string = $CGI::script_name || '-';
	$string .= $CGI::path_info || '';
	push @params, $string;

	# Message, quote newlined area
	$msg =~ s/\n/\n> /g;
	push @params, $msg;
	return join " ", @params;
}

# Return AMOUNT formatted as currency.

sub currency {
    my($amount) = @_;
	my $fmt = "%.2f";
	$fmt = "%." . $Vend::Cfg->{Locale}->{frac_digits} .  "f"
		if $Vend::Cfg->{Locale} && defined $Vend::Cfg->{Locale}->{frac_digits};

    $amount = sprintf $fmt, $amount;
    $amount = commify($amount)
        if is_yes($Vend::Cfg->{'PriceCommas'});

    return international_number($amount);
}


## random_string

# leaving out 0, O and 1, l
my $random_chars = "ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";

# Return a string of random characters.

sub random_string {
    my ($len) = @_;
    $len = 8 unless $len;
    my ($r, $i);

    $r = '';
    for ($i = 0;  $i < $len;  ++$i) {
	$r .= substr($random_chars, int(rand(length($random_chars))), 1);
    }
    $r;
}


sub blank {
    my ($x) = @_;
    return (!defined($x) or $x eq '');
}


# To generate a unique key for caching
# Not very good without MD5
#
my $Md;
my $Keysub;

eval {require MD5 };
if(! $@) {
	$Md = new MD5;
	$Keysub = sub {
					return '' unless @_;
					$Md->reset();
					$Md->add(@_);
					$Md->hexdigest();
				};
}
else {
	$Keysub = sub {
		my $out = '';
		for(@_) {
			$out .= unpack "%32c*", join "", @_;
		}
		$out;
	};
}

sub generate_key { &$Keysub(@_) }

## UNEVAL

# Returns a string representation of an anonymous array, hash, or scaler
# that can be eval'ed to produce the same value.
# uneval([1, 2, 3, [4, 5]]) -> '[1,2,3,[4,5,],]'
# Uses either uneval or Data::Dumper::DumperX

sub uneval {
	&{$Uneval_routine}(@_);
}

sub uneval_it {
    my($o) = @_;		# recursive
    my($r, $s, $i, $key, $value);

	local($) = 0;
    $r = ref $o;
    if (!$r) {
	$o =~ s/([\\"\$@])/\\$1/g;
	$s = '"' . $o . '"';
    } elsif ($r eq 'ARRAY') {
	$s = "[";
	foreach $i (0 .. $#$o) {
	    $s .= uneval_it($o->[$i]) . ",";
	}
	$s .= "]";
    } elsif ($r eq 'HASH') {
	$s = "{";
	while (($key, $value) = each %$o) {
	    $s .= "'$key' => " . uneval_it($value) . ",";
	}
	$s .= "}";
    } else {
	$s = "'something else'";
    }

    $s;
}

# See if Data::Dumper is installed with XSUB
# If it is, session writes will be about 25-30% faster
eval {
		require Data::Dumper;
		import Data::Dumper 'DumperX';
		$Data::Dumper::Indent = 0;
		$Data::Dumper::Terse = 1;
};

if($@) {
	$Uneval_routine = \&uneval_it;
}
else {
	$Uneval_routine = \&Data::Dumper::DumperX;
}

# W

sub writefile {
    my($file, $data) = @_;

	$file = ">>$file" unless $file =~ /^[|>]/;

    eval {
		unless($file =~ s/^[|]\s*//) {
			open(Vend::LOGDATA, "$file") or die "open\n";
			lockfile(\*Vend::LOGDATA, 1, 1) or die "lock\n";
			seek(Vend::LOGDATA, 0, 2) or die "seek\n";
			print(Vend::LOGDATA "$data\n") or die "write to\n";
			unlockfile(\*Vend::LOGDATA) or die "unlock\n";
		}
		else {
            my (@args) = grep /\S/, quoted_string($file);
			open(Vend::LOGDATA, "|-") || exec @args;
			print(Vend::LOGDATA "$data\n") or die "pipe to\n";
		}
		close(Vend::LOGDATA) or die "close\n";
    };
    if ($@) {
		logError "Could not $@ log file '" . $file . "': $!\n" .
    		"to log this data:\n" .  $data ;
		return 0;
    }
	1;
}


# Log data fields to a data file.

sub logData {
    my($file,@msg) = @_;
    my $prefix = '';

	$file = ">>$file" unless $file =~ /^[|>]/;

	my $msg = tabbed @msg;

    eval {
		unless($file =~ s/^[|]\s*//) {
			open(Vend::LOGDATA, "$file")	or die "open\n";
			lockfile(\*Vend::LOGDATA, 1, 1)	or die "lock\n";
			seek(Vend::LOGDATA, 0, 2)		or die "seek\n";
			print(Vend::LOGDATA "$msg\n")	or die "write to\n";
			unlockfile(\*Vend::LOGDATA)		or die "unlock\n";
		}
		else {
            my (@args) = grep /\S/, quoted_string($file);
			open(Vend::LOGDATA, "|-") || exec @args;
			print(Vend::LOGDATA "$msg\n") or die "pipe to\n";
		}
		close(Vend::LOGDATA) or die "close\n";
    };
    if ($@) {
		logError "Could not $@ log file '" . $file . "': $!\n" .
    		"to log this data:\n" .  $msg ;
		return 0;
    }
	1;
}


sub file_modification_time {
    my ($fn) = @_;
    my @s = stat($fn) or die "Can't stat '$fn': $!\n";
    return $s[9];
}


sub quoted_string {

	my ($text) = @_;
	my (@fields);
	push(@fields, $+) while $text =~ m{
	   "([^\"\\]*(?:\\.[^\"\\]*)*)"\s?  ## standard quoted string, w/ possible space
	   | ([^\s]+)\s?                    ## anything else, w/ possible space
	   | \s+                            ## any whitespace
        }gx;
    @fields;
}


sub quoted_comma_string {

my ($text) = @_;
my (@fields);
push(@fields, $+) while $text =~ m{
   "([^\"\\]*(?:\\.[^\"\\]*)*)"[\s,]?  ## std quoted string, w/possible space-comma
   | ([^\s,]+)[\s,]?                   ## anything else, w/possible space-comma
   | [,\s]+                            ## any comma or whitespace
        }gx;
    @fields;
}




## READIN

# Reads in a page from the page directory with the name FILE and ".html"
# appended.  Returns the entire contents of the page, or undef if the
# file could not be read.

sub readin {
    my($file) = @_;
    my($fn, $contents, $dir, $level);
    local($/);
	
	$file =~ s#\.html?$##;
	($dir = $file) =~ s#/[^/]*##;
	$dir = $Vend::Cfg->{'PageDir'} . "/" . $dir;
##print("dirname for readin: $dir\n") if $Global::DEBUG;
	if (-f "$dir/.access") {
		$level = '';
		$level = 3 if -s _;
	}

	if( defined $level and ! check_security($file, $level) ){
		$file = $Vend::Cfg->{SpecialPage}->{violation};
		$fn = $Vend::Cfg->{'PageDir'} . "/" . escape_chars($file) . ".html";
	}
	else {
		$fn = $Vend::Cfg->{'PageDir'} . "/" . escape_chars($file) . ".html";
	}

    if (open(Vend::IN, $fn)) {
		undef $/;
		$contents = <Vend::IN>;
		close(Vend::IN);
    } else {
		$contents = undef;
    }
    $contents;
}

# Reads in an arbitrary file.  Returns the entire contents,
# or undef if the file could not be read.
# Careful, needs the full path, or will be read relative to
# VendRoot..and will return binary. Should be tested by
# the user.
#
# To ensure security in multiple catalog setups, leading
# / is not allowed unless $Global::NoAbsolute is set.
#
sub readfile {
    my($file, $no) = @_;
    my($contents);
    local($/);

##print "Got to readfile '$file'\n" if $Global::DEBUG;

	if($no and ($file =~ m:^\s*/: or $file =~ m#\.\./.*\.\.#)) {
		logError("Can't read file '$file' with NoAbsolute set");
		logGlobal("Can't read file '$file' with NoAbsolute set");
		return undef;
	}

    if (open(Vend::IN, $file)) {
		undef $/;
		$contents = <Vend::IN>;
		close(Vend::IN);
    } else {
		$contents = undef;
    }
    $contents;
}

sub is_yes {
    return( defined($_[$[]) && ($_[$[] =~ /^[yYtT1]/));
}

sub is_no {
	return( !defined($_[$[]) || ($_[$[] =~ /^[nNfF0]/));
}

# Returns a URL which will run the ordering system again.  Each URL
# contains the session ID as well as a unique integer to avoid caching
# of pages by the browser.

sub vendUrl
{
    my($path, $arguments, $r) = @_;
    $r = $Vend::Cfg->{'VendURL'}
		unless defined $r;
	$arguments = '' unless defined $arguments;

	if(defined $Vend::Cfg->{'AlwaysSecure'}->{$path}) {
		$r = $Vend::Cfg->{'SecureURL'};
	}

    $r .= '/' . $path . '?' . $Vend::SessionID .
	';' . $arguments . ';' . ++$Vend::Session->{'pageCount'};
    $r;
}    

sub secure_vendUrl
{
    my($path, $arguments) = @_;
    my($r);
	return undef unless $Vend::Cfg->{'SecureURL'};

	$arguments = $arguments || '';

    $r = $Vend::Cfg->{'SecureURL'} . '/' . $path . '?' . $Vend::SessionID .
	';' . $arguments . ';' . ++$Vend::Session->{'pageCount'};
    $r;
}    

my $debug = 0;
my $use = undef;

### flock locking

# sys/file.h:
my $flock_LOCK_SH = 1;          # Shared lock
my $flock_LOCK_EX = 2;          # Exclusive lock
my $flock_LOCK_NB = 4;          # Don't block when locking
my $flock_LOCK_UN = 8;          # Unlock

sub flock_lock {
    my ($fh, $excl, $wait) = @_;
    my $flag = $excl ? $flock_LOCK_EX : $flock_LOCK_SH;

    if ($wait) {
        flock($fh, $flag) or confess "Could not lock file: $!\n";
        return 1;
    }
    else {
        if (! flock($fh, $flag | $flock_LOCK_NB)) {
            if ($! =~ m/^Try again/
                or $! =~ m/^Resource temporarily unavailable/
                or $! =~ m/^Operation would block/) {
                return 0;
            }
            else {
                confess "Could not lock file: $!\n";
            }
        }
        return 1;
    }
}

sub flock_unlock {
    my ($fh) = @_;
    flock($fh, $flock_LOCK_UN) or confess "Could not unlock file: $!\n";
}


### fcntl locking now done by File::Lock

sub fcntl_lock {
    my ($fh, $excl, $wait) = @_;
	my $cmd = '';
    $cmd .= $excl ? 'w' : 'r';
    $cmd .= $wait ? 'b' : 'n';


    File::Lock::fcntl($fh,$cmd)
    	or confess "Could not lock file: $!\n";
	1;
}

sub fcntl_unlock {
    my ($fh) = @_;
    File::Lock::fcntl($fh,'u')
    	or confess "Could not unlock file: $!\n";
    1;
}

### Select based on os

my $lock_function;
my $unlock_function;

unless (defined $use) {
    my $os = $Vend::Util::Config{'osname'};
    warn "lock.pm: os is $os\n" if $debug;
	$use = 'flock';
    if ($os eq 'solaris') {
        $use = 'fcntl'
			if defined $INC{'File/Lock.pm'};
    }
}
        
if ($use eq 'fcntl') {
    warn "lock.pm: using fcntl locking\n" if $debug;
    $lock_function = \&fcntl_lock;
    $unlock_function = \&fcntl_unlock;
}
else {
    warn "lock.pm: using flock locking\n" if $debug;
    $lock_function = \&flock_lock;
    $unlock_function = \&flock_unlock;
}
    
sub lockfile {
    &$lock_function(@_);
}

sub unlockfile {
    &$unlock_function(@_);
}

# Returns the number ordered of a single item code
# Uses the current cart if none specified.

sub tag_item_quantity {
	my($code,$ref) = @_;
    my($i,$cart);
	
	if(ref $Vend::Session->{carts}->{$ref}) {
		 $cart = $Vend::Session->{carts}->{$ref};
	}
	else {
		$cart = $Vend::Items;
	}

	my $q = 0;
    foreach $i (0 .. $#$cart) {
		$q += $cart->[$i]->{'quantity'}
			if $code eq $cart->[$i]->{'code'};
    }
	$q;
}

# Returns the total number of items ordered.
# Uses the current cart if none specified.

sub tag_nitems {
	my($ref) = @_;
    my($cart, $total, $i);

	
	if(ref $Vend::Session->{carts}->{$ref}) {
		 $cart = $Vend::Session->{carts}->{$ref};
	}
	else {
		$cart = $Vend::Items;
	}

    $total = 0;
    foreach $i (0 .. $#$cart) {
		$total += $cart->[$i]->{'quantity'};
    }
    $total;
}

# AUTOLOAD
#1;
#__END__
# END AUTOLOAD

# Check that the user is authorized by one or all of the
# configured security checks
sub check_security {
	my($item, $reconfig) = @_;

	my $msg;
	if(! $reconfig) {
		return 1 if $CGI::user;
        logGlobal <<EOF;
auth error host=$CGI::host script=$CGI::script_name page=$CGI::path_info
EOF
        return '';  
	}
	elsif($reconfig eq '1') {
		$msg = 'reconfigure catalog';
	}
	elsif ($reconfig eq '2') {
		$msg = "access protected database $item";
	}
	elsif ($reconfig eq '3') {
		$msg = "access administrative function $item";
	}

	# Check if host IP is correct when MasterHost is set to something
	if ($Vend::Cfg->{MasterHost} and
		$Vend::Cfg->{MasterHost} !~ /\b$CGI::host\b/)
	{
		logGlobal <<EOF;
ALERT: Attempt to $msg at $CGI::script_name from:

	REMOTE_ADDR  $CGI::host
	REMOTE_USER  $CGI::user
	USER_AGENT   $CGI::useragent
	SCRIPT_NAME  $CGI::script_name
	PATH_INFO    $CGI::path_info
EOF

		return '';
	}

	# Check to see if password enabled, then check
	if ($Vend::Cfg->{Password} and
		crypt($CGI::reconfigure_catalog, $Vend::Cfg->{Password})
		ne  $Vend::Cfg->{Password})
	{
		logGlobal <<EOF;
ALERT: Password mismatch, attempt to $msg at $CGI::script_name from $CGI::host
EOF
			return '';
	}

	# Finally ceck to see if remote_user match enabled, then check
	if ($Vend::Cfg->{RemoteUser} and
		$CGI::user ne $Vend::Cfg->{RemoteUser})
	{
		logGlobal <<EOF;
ALERT: Attempt to $CGI::script_name $msg at with improper user name:

	REMOTE_ADDR  $CGI::host
	REMOTE_USER  $CGI::user
	USER_AGENT   $CGI::useragent
	SCRIPT_NAME  $CGI::script_name
	PATH_INFO    $CGI::path_info
EOF
		return '';
	}

	# Don't allow random reconfigures without one of the three checks
	unless ($Vend::Cfg->{MasterHost} or $Vend::Cfg->{Password}
			or $Vend::Cfg->{RemoteUser}) {
		logGlobal <<EOF;
Attempt to $msg on $CGI::script_name, secure operations disabled.

	REMOTE_ADDR  $CGI::host
	REMOTE_USER  $CGI::user
	USER_AGENT   $CGI::useragent
	SCRIPT_NAME  $CGI::script_name
	PATH_INFO    $CGI::path_info
EOF
			return '';

	}

	# Authorized if got here
#print("Checked security: $msg\n") if $Global::DEBUG;
	return 1;
}

# Replace the escape notation %HH with the actual characters.
#
#sub unescape_chars {
#    my($in) = @_;
#
#    $in =~ s/%(..)/chr(hex($1))/ge;
#    $in;
#}

# Returns its arguments as a string of comma separated and quoted
# fields.  Double quotes in the argument values are converted to
# two double quotes.

sub csv {
    return join(',', map { $_ = '' unless defined $_;
                           s/\"/\"\"/g;
                           '"'. $_ .'"';
                         } @_);
}

## SEND_MAIL

# Send a mail message to the email address TO, with subject SUBJECT, and
# message BODY.  Returns true on success.

sub send_mail {
    my($to, $subject, $body) = @_;
	my($reply) = '';
    my($ok);

	$reply = "Reply-To: $Vend::Session->{'values'}->{'mv_email'}\n"
		if defined $Vend::Session->{'values'}->{'mv_email'};

    $ok = 0;
    SEND: {
		open(Vend::MAIL,"|$Vend::Cfg->{'SendMailProgram'} $to") or last SEND;
		my $mime = '';
		$mime = Vend::Interpolate::do_tag('mime header') if defined $Vend::MIME;
		print Vend::MAIL "To: $to\n", $reply, "Subject: $subject\n$mime\n"
	    	or last SEND;
		if (defined $Vend::MIME) {
			print Vend::MAIL Vend::Interpolate::do_tag('mime Order text', $body)
				or last SEND;
		}
		else {
			print Vend::MAIL $body
				or last SEND;
		}
		print Vend::MAIL Vend::Interpolate::do_tag('mime boundary') . '--'
			if defined $Vend::MIME;
		close Vend::MAIL or last SEND;
		$ok = ($? == 0);
    }
    
    if (!$ok) {
		logError("Unable to send mail using $Vend::Cfg->{'SendMailProgram'}\n" .
		 	"To: $to\n" .
		 	"Subject: $subject\n" .
		 	"Reply-to: $reply\n\n$body");
    }

    $ok;
}

sub tainted {
    my($v) = @_;
    my($r);
    local($@);

    eval { open(Vend::FOO, ">" . "FOO" . substr($v,0,0)); };
    close Vend::FOO;
    ($@ ? 1 : 0);
}

# Appends the string $value to the end of $filename.  The file is opened
# in append mode, and the string is written in a single system write
# operation, so this function is safe in a multiuser environment even
# without locking.

sub append_to_file {
    my ($filename, $value) = @_;

    open(OUT, ">>$filename") or die "Can't append to '$filename': $!\n";
    syswrite(OUT, $value, length($value))
        == length($value) or die "Can't write to '$filename': $!\n";
    close(OUT);
}

# Converts the passed field values into a single line in Ascii delimited
# format.  Two formats are available, selected by $format:
# "comma_separated_values" and "tab_separated".

sub field_line {
    my $format = shift;

    return csv(@_) . "\n"    if $format eq 'comma_separated_values';
    return tabbed(@_) . "\n" if $format eq 'tab_separated';

    die "Unknown format: $format\n";
}

# Appends the passed field values onto the end of $filename in a single
# system operation.

sub append_field_data {
    my $filename = shift;
    my $format = shift;

    append_to_file($filename, field_line($format, @_));
}

## ERROR

# Log the error MSG to the error file.

sub logDebug {
	return unless $Global::DebugMode;
	print @_ . "\n";
}

sub logGlobal {
    my($msg) = @_;
	my(@params);
    $msg = format_log_msg($msg);

    eval {
		open(Vend::ERROR, ">>$Global::ErrorFile") or die "open\n";
		lockfile(\*Vend::ERROR, 1, 1) or die "lock\n";
		seek(Vend::ERROR, 0, 2) or die "seek\n";
		print(Vend::ERROR $msg, "\n") or die "write to\n";
		unlockfile(\*Vend::ERROR) or die "unlock\n";
		close(Vend::ERROR) or die "close\n";
    };
    if ($@) {
		chomp $@;
		print "\nCould not $@ error file '";
		print $Global::Errorfile, "':\n$!\n";
		print "to report this error:\n", $msg;
		exit 1;
    }
}


# Log the error MSG to the error file.

sub logError {
    my($msg) = @_;
	my(@params);
	return unless defined $Vend::Cfg;

	$Vend::Session->{'last_error'} = $msg;

    $msg = format_log_msg($msg);

    eval {
		open(Vend::ERROR, ">>$Vend::Cfg->{ErrorFile}")
											or die "open\n";
		lockfile(\*Vend::ERROR, 1, 1)		or die "lock\n";
		seek(Vend::ERROR, 0, 2)				or die "seek\n";
		print(Vend::ERROR $msg, "\n")		or die "write to\n";
		unlockfile(\*Vend::ERROR)			or die "unlock\n";
		close(Vend::ERROR)					or die "close\n";
    };
    if ($@) {
		chomp $@;
		logGlobal <<EOF;
Could not $@ error file $Vend::Cfg->{ErrorFile}: $!
		
to report this error:
$msg
EOF
    }
}

1;
