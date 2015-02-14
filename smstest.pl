#!perl

use strict;
use warnings;
use LWP::Simple qw();
use JSON;
use Data::Dumper;
use constant DEBUG => 0;
use FindBin;


my $APIKey;
my $APISecret;
if(!LoadAPIData()){
	SaveAPIData();
}

my $TokenURL = "https://api.telstra.com/v1/oauth/token?client_id=$APIKey&client_secret=$APISecret&grant_type=client_credentials&scope=SMS";
my $MessageURL = "https://api.telstra.com/v1/sms/messages";


our $AccessToken = "";
our $AccessExpiry = time - 10;#default to expired
my $ua = LWP::UserAgent->new;
$ua->timeout(60);
$ua->agent('SMS Testing/1.0');

Promt();
####User Interaction Functions####
sub Promt{
	print "1: Send\n";
	print "2: Status\n";
	print "3: Get Reply\n";
	print "0: Exit\n";
	print "?:";
	my $Process = <STDIN>;
	chomp $Process;
	if($Process eq "1"){
		SendPrompt();
		Promt();
	}elsif($Process eq "2"){
		StatusPrompt();
		Promt();
	}elsif($Process eq "3"){
		ReplyPrompt();
		Promt();
	}elsif($Process eq "0"){
		PrintData();
		exit;
	}else{
		print "No!";
		exit;
	}
}

sub SendPrompt{
	print "Mobile Number:";
	my $MobNum = <STDIN>;
	chomp $MobNum;
	if($MobNum !~ /^\d{10}$/){
		print "Mobile Number not acceptable";
		exit;
	}
	print "Message:";
	my $Message = <STDIN>;
	chomp $Message;
	if(length($Message)>160){
		print "Message is longer than 160 chars";
		exit;
	}
	my $MessageId = SendSMS(Number=>$MobNum, Message=>$Message);
	print "MessageId: $MessageId\n";
	print "\n^^^^^^^^^^^^^^^^^^^^^^^^\n\n";
}
sub StatusPrompt{
	print "MessageId:";
	my $MessageId = <STDIN>;
	chomp $MessageId;
	if($MessageId !~ /^[\dA-Z]{10,30}$/){
		print "MessageId not acceptable";
		exit;
	}
	GetSMSStatus(MessageId=>$MessageId);
	print "\n^^^^^^^^^^^^^^^^^^^^^^^^\n\n";
}

sub ReplyPrompt{
	print "MessageId:";
	my $MessageId = <STDIN>;
	chomp $MessageId;
	if($MessageId !~ /^[\dA-Z]{10,30}$/){
		print "MessageId not acceptable";
		exit;
	}
	GetSMSReply(MessageId=>$MessageId);
	print "\n^^^^^^^^^^^^^^^^^^^^^^^^\n\n";
}


####API Functions####
sub GetAccessToken{
	return if IsAccessTokenValid();
	my $request = HTTP::Request->new('GET', $TokenURL);
	my $response = $ua->request($request);
	if($response->is_success){
		my $RespData = from_json($response->decoded_content);
		$AccessToken = $RespData->{access_token};
		$AccessExpiry = time + $RespData->{expires_in};
		print "Token resp Json decoded\n", Dumper($RespData) if DEBUG;
	}else{
		die print "GetAccessToken failed: ", $response->status_line;
	}
}
sub IsAccessTokenValid{
	if(($AccessExpiry - time)<=60){#invalidate token if will expire in less than 60 seconds or if already expired
		return 0;
	}else{
		return 1;
	}
}

sub SendSMS{
	my %inputs = @_;
	die print "SendSMS: Number not provided" if !defined $inputs{Number};
	die print "SendSMS: Message not provided" if !defined $inputs{Message};
	die print "SendSMS: Message > 160 chars" if length($inputs{Message}) > 160;
	GetAccessToken();

	my $request = HTTP::Request->new('POST', $MessageURL);
	my $json = qq^{"to":"$inputs{Number}","body":"$inputs{Message}"}^;
	$request->header( 'Content-Type' => 'application/json' );
	$request->header( 'Authorization' => "Bearer $AccessToken" );
	$request->content( $json );

	my $response = $ua->request($request);
	if($response->is_success){
		my $RespData = from_json($response->decoded_content);
		print "Send resp Json decoded\n", Dumper($RespData) if DEBUG;
		return $RespData->{messageId};
		
	}else{
		die print "SendSMS failed: ", $response->status_line;
	}
}

sub GetSMSStatus{
	my %inputs = @_;
	die print "GetSMSStatus: MessageId not provided" if !defined $inputs{MessageId};
	GetAccessToken();
	
	my $request = HTTP::Request->new('GET', $MessageURL . "/$inputs{MessageId}");
	$request->header( 'Authorization' => "Bearer $AccessToken" );
	
	my $response = $ua->request($request);
	if($response->is_success){
		my $RespData = from_json($response->decoded_content);
		print "status: ", $RespData->{status}, "\n";
		print "to: ", $RespData->{to}, "\n";
		print "sentTimestamp: ", $RespData->{sentTimestamp}, "\n";
		print "receivedTimestamp: ", $RespData->{receivedTimestamp}, "\n";
		print "Send Status resp Json decoded\n", Dumper($RespData) if DEBUG;
	}else{
		die print "GetSMSStatus failed: ", $response->status_line;
	}
}

sub GetSMSReply{
	my %inputs = @_;
	die print "GetSMSReply: MessageId not provided" if !defined $inputs{MessageId};
	GetAccessToken();
	
	my $request = HTTP::Request->new('GET', $MessageURL . "/$inputs{MessageId}/response");
	$request->header( 'Authorization' => "Bearer $AccessToken" );
	
	my $response = $ua->request($request);
	if($response->is_success){
		my $RespData = from_json($response->decoded_content);
		print "Send Status resp Json decoded\n", Dumper($RespData) if DEBUG;
		if($RespData->[0]{acknowledgedTimestamp} eq 'N/A'){
			print "No reply avilable\n";
		}else{
			foreach my $Resp (@{$RespData}){
				print "*Message Response:\n";
				print "from: ", $Resp->{from}, "\n";
				print "acknowledgedTimestamp: ", $Resp->{acknowledgedTimestamp}, "\n";
				print "content: ", $Resp->{content}, "\n";
			}
		}
	}else{
		die print "GetSMSReply failed: ", $response->status_line;
	}
}

#Setup functions
sub LoadAPIData{
	if(-e $FindBin::Bin . "/api.dat"){
		open(my $APIDATA, '<', $FindBin::Bin . "/api.dat") || die print "Unable to open api data file: $!";
		while(my $line = <$APIDATA>){
			chomp $line;
			my @line = split(",", $line);
			if($line[0] eq 'APIKey'){
				$APIKey = $line[1];
				print "Read API Key from File:$APIKey:\n" if DEBUG;
			}elsif($line[0] eq 'APISecret'){
				$APISecret = $line[1];
				print "Read API Secret from File:$APISecret:\n" if DEBUG;
			}
		}
		close($APIDATA);
		if((!defined $APIKey) || (!defined $APISecret)){
			return 0;
		}
		return 1;
	}else{
		return 0;
		
	}
}

sub SaveAPIData{
	print "API Data Setup Required\n";
	print "API Key:";
	my $Ak = <STDIN>;
	chomp $Ak;
	if($Ak !~ /^[A-Z\d]{10,100}$/i){
		print "API Key not acceptable";
		exit;
	}
	print "API Secret:";
	my $As = <STDIN>;
	chomp $As;
	if($As !~ /^[A-Z\d]{10,100}$/i){
		print "API Secret not acceptable";
		exit;
	}
	open(my $APIDATA, '>', $FindBin::Bin . "/api.dat") || die print "Unable to open api data file: $!";
	print $APIDATA "APIKey,$Ak\n";
	print $APIDATA "APISecret,$As";
	close($APIDATA);
	$APIKey = $Ak;
	$APISecret = $As;
	PrintData();
	print "\n";
}

####Debug Functions####
sub PrintData{
	print "**************PrintData*********\n";
	print "Now: ", time, "\n";
	print "AccessToken: $AccessToken\n";
	print "AccessExpiry: $AccessExpiry\n";
	my $expiry = $AccessExpiry - time;
	print "AccessExpires In: $expiry seconds\n";
	print "********************************\n";
}

