#################################################################
#
# A module to plot Inverterdata from SMA - Solar Technology
#
# Originally written 2013 by Sven Koethe <sven at koethe-privat dot de>
#
# The modul uses on SBFSpot - Linux Tool
#
#################################################################
# Definition: define <name> SMAUtils <address> <path-to-sbfspot>
# Parameters:
#   address  - Specify the BT/IP-Address of your Inverter
#   path-sbfspot - Specify path to SBFspot utility, can be either
#                  relative to FHEM Home or absolute
# Custom attributes:
#   interval - Specify the delay time for update the readings
#
#################################################################
# Versions History
#
# 2.2       16.09.2016     SMAUtils_Attr added
# 2.1       16.09.2016     sub Define changed
# 2.0       06.09.2016     attribute mode
package main;

use strict;
use warnings;
use MIME::Base64;
use Blocking;


###################################
# Initialize module and define
# available end points and
# attributes
###################################
sub SMAUtils_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    = "SMAUtils_Define";
	$hash->{GetFn}    = "SMAUtils_Get";
	$hash->{UndefFn}  = "SMAUtils_Undef";
	$hash->{AttrFn}   = "SMAUtils_Attr";
	$hash->{AttrList} = "interval ". "timeout ". "mode:manual,automatic ". "disable:0,1 ". $readingFnAttributes;
}

###################################
# Module Definition
###################################
sub SMAUtils_Define($$) {
	my ( $hash, $def ) = @_;
	my $name = $hash->{NAME};

	my @a = split( "[ \t][ \t]*", $def );

	if ( int(@a) < 3 ) {
		return "You need to specify more parameters.\n". "Format: define <name> SMAUtils <address> <path-to-sbfspot>";
	}

	my $address = $a[2];
	$hash->{TOOLPATH} = $a[3];

	unless (
		( $address =~ /^\s*([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\s*$/ )
		|| ( $address =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/
			&& ( ( $1 <= 255 && $2 <= 255 && $3 <= 255 && $4 <= 255 ) ) )
	  ){
		return "given address is not a valid bluetooth or IP address";
	} else {
		$hash->{ADDRESS} = $address;
	}

	return;
}

####################################
# Get a value in a non-blocking way
####################################
sub SMAUtils_Get($$) {
	my ( $hash, @a ) = @_;
	return "\"get X\" needs at least an argument" if ( @a < 2 );
	my $name = shift @a;
	my $opt  = shift @a;

	my $getlist = "Unknown argument $opt, choose one of " . "data:noArg ";

	return "module is deactivated" if ( IsDisabled($name) );

	if ( $opt eq "data" ) {

		# "1" ist Statusbit f�r manuelle Abfrage
		Inverter_CallData( $hash, 1 );
	} else {
		return "$getlist";
	}

}

#####################################
# Check for valid attributes
#####################################
sub SMAUtils_Attr {
	my ( $cmd, $name, $aName, $aVal ) = @_;

	# $cmd can be "del" or "set"
	# $name is device name
	# aName and aVal are Attribute name and value
	my $hash = $defs{$name};
	if ($cmd eq "set") {
		if ( $aName eq "mode" ) {
			readingsSingleUpdate( $hash, "state", $aVal, 1 );
		} elsif ( $aName eq "interval" ) {
			delete( $hash->{helper}{RUNNING_PID} )
			  if ( defined( $hash->{helper}{RUNNING_PID} ) );
			RemoveInternalTimer($hash);

			# Start call timer.
			if ( AttrVal( $name, "mode", "automatic" ) eq "automatic" ) {
				# "0" is call mode
				InternalTimer( gettimeofday() + $aVal,"Inverter_CallData", $hash, 0 );
			}
		}
	} elsif ($cmd eq "del") {
		if ( $aName eq "interval") {
			RemoveInternalTimer($hash);
		}
	}

	return undef;
}

#####################################
# Remove the module
#####################################
sub SMAUtils_Undef($$) {
	my ( $hash, $arg ) = @_;

	RemoveInternalTimer($hash);

	BlockingKill( $hash->{helper}{RUNNING_PID} )
	  if ( defined( $hash->{helper}{RUNNING_PID} ) );

	return undef;
}

#####################################
##  Main loop BlockingCall
#####################################
sub Inverter_CallData($$) {
	my ( $hash, $mode ) = @_;
	my $name = $hash->{NAME};
	my $timeout = AttrVal( $name, "timeout", 30 );

	if ( !AttrVal( $name, "disable", undef ) ) {
		if ( exists( $hash->{helper}{RUNNING_PID} ) ) {
			Log3 $name, 1,"$hash->{NAME} - Error: another BlockingCall is already running, can't start BlockingCall Inverter_CallData";
		}else {
			$hash->{helper}{RUNNING_PID} =BlockingCall( "Get_Inverterdata", $name, "Parse_Inverterdata",$timeout, "ParseInverterdata_Aborted", $hash );
		}
	}else {
		readingsBeginUpdate($hash);
		readingsBulkUpdate( $hash, "state",   "disabled" );
		readingsBulkUpdate( $hash, "summary", "disabled" );
		readingsEndUpdate( $hash, 1 );

		Log3 $name, 5, "$hash->{NAME} - is currently disabled";
	}

	if ( AttrVal( $name, "mode", "automatic" ) eq "automatic" ) {
		RemoveInternalTimer( $hash, "Inverter_CallData" );
		InternalTimer( gettimeofday() + AttrVal( $name, "interval", undef ),"Inverter_CallData", $hash, 0 );
	}

	return;
}

#####################################
##  Retrieve Inverter Data using
##  SBFSpot
#####################################
sub Get_Inverterdata {
	my ($name) = @_;
	my $hash   = $defs{$name};
	my $data   = "";

	Log3 $name, 4, "$hash->{NAME} start BlockingCall Get_Inverterdata";

    my $toolpath = $hash->{TOOLPATH};
	$data .= qx( $toolpath -nocsv -nosql -v );

	Log3 $name, 5,"$hash->{NAME} BlockingCall Get_Inverterdata Data returned:" . "\n". "$data";

	# Data has to be returned in one row.
	my $dataenc = encode_base64( $data, "" );

	Log3 $name, 5,"$hash->{NAME} BlockingCall Get_Inverterdata Data Base64: $dataenc";

	Log3 $name, 4, "$hash->{NAME} BlockingCall Get_Inverterdata finished";

	return "$name|$dataenc";
}

######################################
##  Parse Data from SBFspot and set
##  readings
######################################
sub Parse_Inverterdata($) {
	my ($string) = @_;
	my @a = split( "\\|", $string );

	my $hash     = $defs{ $a[0] };
	my $name     = $hash->{NAME};
	my $response = decode_base64( $a[1] );

	Log3 $hash->{NAME}, 4,"$hash->{NAME} start BlockingCall Parse_Inverterdata";

	my $err_log = '';
	my %pos;

	# parse retrieve data from inverter
	my @lines = split /\n/, $response;

	my $readingsname  = '';
	my $readingsvalue = '';
	my $value         = '';
	my $substr        = '';

	readingsBeginUpdate($hash);

	my $end = 0;
	my $i   = 0;
	foreach my $line (@lines) {
		if ( $i > 16 && $end != 1 ) {
			$pos{$line} = index( $response, $line );
			my @reading = split( ":", $line, 2 );

			$readingsname = ltrim( $reading[0] );
			$readingsname = rtrim($readingsname);
			$readingsname = lc($readingsname);
			$readingsname =~ s/ /_/g;

			$readingsvalue = ltrim( $reading[1] );

			$substr = 'freq';

			if ( index( $readingsname, $substr ) != -1 ) {
				$value = ltrim( $reading[1] );
				$value =~ /(\d+(?:\.\d+)?)/;
				$readingsvalue = $1;
			}

			$substr = 'phase';

			if ( index( $readingsname, $substr ) != -1 ) {
				my $linesreading = substr $readingsname, 0, 7;
				my $linesvalue = substr $line, 8;
				my @line_readings = split( "-", $linesvalue );

				foreach my $line_readings (@line_readings) {
					@reading      = split( ":", $line_readings );
					$readingsname = ltrim( $reading[0] );
					$readingsname = $linesreading . "_" . $readingsname;
					$readingsname = rtrim($readingsname);
					$readingsname = lc($readingsname);
					$readingsname =~ s/ /_/g;

					$value = ltrim( $reading[1] );
					$value =~ /(\d+(?:\.\d+)?)/;
					$readingsvalue = $1;

					readingsBulkUpdate( $hash, $readingsname, $readingsvalue );
				}
			}

			$substr = 'total';

			if ( index( $readingsname, $substr ) != -1 ) {
				$value = ltrim( $reading[1] );
				$value =~ /(\d+(?:\.\d+)?)/;
				$readingsvalue = $1;
			}

			$substr = 'today';

			if ( index( $readingsname, $substr ) != -1 ) {
				$value = ltrim( $reading[1] );
				$value =~ /(\d+(?:\.\d+)?)/;
				$readingsvalue = $1;
			}

			$substr = 'string';

			if ( index( $readingsname, $substr ) != -1 ) {
				my $linesreading = substr $readingsname, 0, 8;
				my $linesvalue = substr $line, 9;
				my @line_readings = split( "-", $linesvalue );

				foreach my $line_readings (@line_readings) {
					@reading      = split( ":", $line_readings );
					$readingsname = ltrim( $reading[0] );
					$readingsname = $linesreading . "_" . $readingsname;
					$readingsname = rtrim($readingsname);
					$readingsname = lc($readingsname);
					$readingsname =~ s/ /_/g;

					$value = ltrim( $reading[1] );
					$value =~ /(\d+(?:\.\d+)?)/;
					$readingsvalue = $1;

					readingsBulkUpdate( $hash, $readingsname, $readingsvalue );
				}
			}

			$substr = 'starttime';

			if ( index( $readingsname, $substr ) == -1 ) {
				readingsBulkUpdate( $hash, $readingsname, $readingsvalue );
			}

			$substr = 'Sleep';

			if ( index( $line, $substr ) != -1 ) {
				$end = 1;
			}
		}

		$i++;
	}
	my $mode =
	  ( AttrVal( $name, "mode", "automatic" ) eq "automatic" )
	  ? "automatic"
	  : "manual";
	readingsBulkUpdate( $hash, "state",   $mode );
	readingsBulkUpdate( $hash, "summary", "enabled" );
	readingsEndUpdate( $hash, 1 );

	Log3 $hash->{NAME}, 4,"$hash->{NAME} BlockingCall Parse_Inverterdata finished";
	delete( $hash->{helper}{RUNNING_PID} );

	return;
}

#######################################
##  Timeout  BlockingCall
#######################################
sub ParseInverterdata_Aborted($) {
	my ($hash) = @_;

	Log3 $hash, 1, "$hash->{NAME} -> BlockingCall Get_Inverterdata timed out";
	delete( $hash->{helper}{RUNNING_PID} );
}

1;

