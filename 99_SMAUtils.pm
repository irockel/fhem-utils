##############################################
#
# A module to plot Inverterdata from SMA - Solar Technology
#
# written 2013 by Sven Koethe <sven at koethe-privat dot de>
#
# The modul is based on SBFSpot - Linux Tool
#
# Projectpage: https://code.google.com/p/sma-spot/
#
##############################################
# Definition: define <name> SMAUtils <btaddress> <delay>
# Parameters:
#   btaddress - Specify the BT-Address of your Inverter
#   delay - Specify the delay time for update the readings
#
##############################################
# $Id: 99_SMAUtils.pm

package main;

use strict;
use warnings;

my $MODUL = "SMAUtils";

###################################

sub SMAUtils_Initialize($) {
    my ($hash) = @_;
    $hash->{DefFn}   = "SMAUtils_Define";
    $hash->{UndefFn} = "SMAUtils_Undef";

    $hash->{AttrList} = "delay " . $readingFnAttributes;
}

###################################

sub SMAUtils_Define($$) {
    my ( $hash, $def ) = @_;
    my $name = $hash->{NAME};

    my @a = split( "[ \t][ \t]*", $def );

    my $btaddress = $a[2];
    my $delay     = $a[3];
    $attr{$name}{delay} = $delay if $delay;

    my $bt = check_bt_address( $a[2] );

    $hash->{ADDRESS} = $btaddress;

    InternalTimer( gettimeofday() + $delay, "SMAUtils_GetStatus", $hash, 0 );

    return undef;
}

#####################################

sub check_bt_address($) {
    my ($address) = @_;
    my $msg = '';
    unless (
        ( $address =~ /^\s*([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\s*$/ )
        || ( $address =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/
            && ( ( $1 <= 255 && $2 <= 255 && $3 <= 255 && $4 <= 255 ) ) )
      )
    {
        return $msg =
          errorlog( "given address is not a valid bluetooth or IP address", 2 );
    }
    return $msg;
}

sub errorlog($$) {
    my ( $msg, $level ) = @_;
    Log $level, $MODUL . ": " . $msg;
    return $msg;
}

#####################################

sub SMAUtils_Undef($$) {
    my ( $hash, $arg ) = @_;

    RemoveInternalTimer($hash);
    return undef;
}

#############################################

sub SMAUtils_FirstInit($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $attrDelayCounter = AttrVal( $name, "delayCounter", "?" );

    if ( !defined( $hash->{delayCounter} ) ) {
        if ( $attrDelayCounter eq "?" ) {
            $hash->{delayCounter} = 0;
            Log 3, "delayCounter not defined";
        }
        else {
            $hash->{delayCounter} = $attrDelayCounter;
            Log 3, "delayCounter is defined";
        }
    }
}

#####################################

sub SMAUtils_GetStatus($) {
    my ($hash) = @_;
    my $err_log = '';
    my $line;
    my $name      = $hash->{NAME};
    my $btaddress = $hash->{ADDRESS};
    my $llevel    = GetLogLevel( $name, 4 );
    my $sdCurTime = gettimeofday();
    my $hour      = SMAUtils_GetHourSD($sdCurTime);
    my %pos;

    # attribute sind noch nicht ausgewertet
    if ( !defined( $hash->{delayCounter} ) ) {
        SMAUtils_FirstInit($hash);
    }

    my $delayCounter = $hash->{delayCounter};

    # wenn delayCounter aktiv
    if ( $delayCounter > 0 ) {
        $delayCounter--;
        if ( $delayCounter == 0 ) {
            $hash->{delayCounter} = AttrVal( $name, "delayCounter", "0" );
        }
        else {
            $hash->{delayCounter} = $delayCounter;
        }
    }
    elsif ( AttrVal( $name, "delayCounter", "0" ) ne "0" ) {
        $hash->{delayCounter} = AttrVal( $name, "delayCounter", "0" );
        $delayCounter = $hash->{delayCounter};
        Log $llevel, "SMAUtils delayCounter restarted";
    }

    my $delay = AttrVal( $name, "delay", 300 );
    InternalTimer( gettimeofday() + $delay, "SMAUtils_GetStatus", $hash, 0 );

    my $i             = 0;
    my $response      = Get_Inverterdata();
    my @lines         = split /\n/, $response;
    my $readingsname  = '';
    my $readingsvalue = '';
    my $value         = '';
    my $end           = 0;
    my $substr        = '';

    readingsBeginUpdate($hash);

    foreach my $line (@lines) {
        if ( $i > 16 && $end != 1 ) {
            $pos{$line} = index( $response, $line );

            # Log 3, "Inverter returned: $line";
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

    readingsEndUpdate( $hash, 1 );

    $hash->{STATE} = "active";

    return;
}

#############################################
sub SMAUtils_GetHourSD($) {
    my @t = localtime(shift);
    return $t[2];
}

#############################################
# aktuelle zeit abgerundet auf stunden

sub SMAUtils_GetDateTrunc($) {
    my @t = localtime(shift);
    return sprintf(
        "%04d-%02d-%02d %02d:%02d:%02d",
        $t[5] + 1900,
        $t[4] + 1,
        $t[3], $t[2], 0, 0
    );
}

#############################################
# zeit wird in serielles format (real) gewandelt
sub SMAUtils_DateStr2Serial($) {
    my $datestr = shift;
    my ( $yyyy, $mm, $dd, $hh, $mi, $ss ) =
      $datestr =~ /(\d+)-(\d+)-(\d+) (\d+)[:](\d+)[:](\d+)/;

    # months are zero based
    my $t2 = fhemTimeLocal( $ss, $mi, $hh, $dd, $mm - 1, $yyyy - 1900 );
    return $t2;
}

sub Get_Inverterdata {
    my $ret = "";
    $ret .= qx( /opt/fhem/SBFspot/SBFspot -nocsv -finq -v );

    Log 3, "SMAspot called";

    return $ret;
}

sub readItem {
    my ( $line, $pos, $align, $item ) = @_;
    my $x;

    if ( $align eq "l" ) {
        $x = substr( $line, $pos );
        my @xa = split( ":", $x );
        $x = $xa[0];    # after two spaces => next field
    }
    if ( $align eq "r" ) {
        $pos += length($item);
        $x = substr( $line, 0, $pos );
        $x =~ s/^.+  //g;    # remove all before the item
    }
    return $x;
}

1;

