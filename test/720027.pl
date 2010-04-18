#!/usr/bin/perl
#

$hexcommand="02313832300030010000c00000303035313030303831303234303434383236383331343135353430303030303030303030343135353430303003";

convert($hexcommand);

print "DERRIVED OCTAL\n$octcommand\n\n";
$goodoct="\2\61\70\62\60\0\60\1\0\0\300\0\0\60\60\65\61\60\60\60\70\61\60\62\64\60\64\64\70\62\66\70\63\61\65\65\64\60\60\60\60\60\60\60\60\60\60\64\61\65\65\64\60\60\60\3";
print "GOOD OCTAL\n$goodoct\n\n";

sub convert {
	$hexcommand=shift;
	$length = length($hexcommand);							
	$tot = ($length/2)-1;                           	
	print "length is: $length\n";
	print "tot is: $tot\n";
	for ($x=0; $x<=$tot; $x++){                     		
		$chunk = substr($hexcommand, $offset, 2);    			
		$dec = &hex2dec($chunk);
		$octbyte=sprintf "%lo", $dec;	
		$octcommand = $octcommand . "\\" . $octbyte;
		$offset+=2;                                  
	}
	return $octcommand;
}

sub hex2dec($) { return hex $_[0] }

