#! /usr/bin/perl -w
# Mtik.pm - a simple Mikrotik Router API client
# Version 1.2 Beta
# Hugh Messenger - hugh at alaweb dot com
# Released under Creative Commons license.
# Do with it what you will, but don't blame me!
#----------------

package Mtik;
$VERSION = '0.02';
$debug = 0;
$error_msg = '';

our($ssloff);
our($sslvm);

use strict;
use vars qw(
            $VERSION
            @ISA
            @EXPORT
            @EXPORT_OK
            $debug
            $error_msg
           );

use IO::Socket;
use IO::Socket::SSL qw(debug0);
use Digest::MD5;
use Data::Dumper;


@ISA        = qw(Exporter);
@EXPORT     = qw();
@EXPORT_OK  = qw(
                 $debug
                 $error_msg
                );
                
my($sock);

sub mtik_connect
{
    my($host) = shift;
    my($port) = shift || 8729;
    if (!($host))
    {
        print "no host!\n";
        return 0;
    }
	my($sock);
	if(defined $ssloff)
	{
		#SSL off (use flag -s)
		$sock = new IO::Socket::INET(
						PeerAddr => $host,
						PeerPort => $port,
						Proto    => 'tcp');
	}
	else
	{
		#print "$sslvm\n";
		#SSL on (Default)
		$sock = new IO::Socket::SSL(
						PeerAddr => $host,
						PeerPort => $port,
						SSL_verify_mode => $sslvm,#; #$sslvm
						SSL_ca_path => '/etc/ssl/certs',
						Timeout => 5);
						
		#SSL_verify_mode. 0x00 (default, does no authentication),
		#				  0x01 (verify peer),
		#				  0x02 (fail verify if no peer cert exists; ignored for clients),
		#			  	  0x04 (verify client once).
		#SSL_verifycn_name
	}
    if (!($sock))
    {
        #print "no socket :$!\n";
	print "No socket ($host:$port) - $!\n";
        return 0;
    }
    return $sock;
}

sub write_word {
    my($word) = shift;
    &write_len(length($word));
    print $sock $word;
}

sub write_sentence {
    my($sentence_ref) = shift;
    my(@sentence) = @$sentence_ref;
    foreach my $word (@sentence)
    {
        write_word($word);
        if ($debug > 2)
        {
            print ">>> $word\n";
        }
    }
    write_word('');
}

sub write_len {
    my($len) = shift;
    if ($len < 0x80)
    {
        print $sock chr($len);
    }
    elsif ($len < 0x4000)
    {
        $len |= 0x8000;
        print $sock chr(($len >> 8) & 0xFF);
        print $sock chr($len & 0xFF);
    }
    elsif ($len < 0x200000)
    {
        $len |= 0xC00000;
        print $sock chr(($len >> 16) & 0xFF);
        print $sock chr(($len >> 8) & 0xFF);
        print $sock chr($len & 0xFF);
    }
    elsif ($len < 0x10000000)
    {
        $len |= 0xE0000000;
        print $sock chr(($len >> 24) & 0xFF);
        print $sock chr(($len >> 16) & 0xFF);
        print $sock chr(($len >> 8) & 0xFF);
        print $sock chr($len & 0xFF);
    }
    else
    {
		print $sock chr(0xF0);
        print $sock chr(($len >> 24) & 0xFF);
        print $sock chr(($len >> 16) & 0xFF);
        print $sock chr(($len >> 8) & 0xFF);
        print $sock chr($len & 0xFF);
    }
}

sub read_byte{
	my $line;
	if(defined $ssloff)
	{
		#SSL off
		$sock->recv($line,1);
	}
	else
	{
		#SSL on
		sysread($sock,$line,1);
	}
	return ord($line);
}

sub read_len {
    if ($debug > 4)
    {
        print "start read_len\n";
    }
	
    my $len = read_byte();
	
    if (($len & 0x80) == 0x00)
	{
		return $len
    }
	elsif (($len & 0xC0) == 0x80)
	{
        $len &= ~0x80;
        $len <<= 8;
        $len += read_byte();
    }
    elsif (($len & 0xE0) == 0xC0)
    {
		$len &= ~0xC0;
        $len <<= 8;
        $len += read_byte();
        $len <<= 8;
        $len += read_byte();
    }
    elsif (($len & 0xF0) == 0xE0)
    {
        $len &= ~0xE0;
        $len <<= 8;
        $len += read_byte();
        $len <<= 8;
        $len += read_byte();       
        $len <<= 8;
        $len += read_byte();       
    }
    elsif (($len & 0xF8) == 0xF0)
    {
        $len = read_byte();
        $len <<= 8;
        $len += read_byte();
        $len <<= 8;
        $len += read_byte();       
        $len <<= 8;
        $len += read_byte();  
	} 
    if ($debug > 4)
    {
        print "read_len got $len\n";
    }
    return $len;
}

sub read_word {
    my($ret_line) = '';
    my($len) = &read_len();
    if ($len > 0)
    {
        if ($debug > 3)
        {
            print "recv $len\n";
        }
        while (1) {
            my($line) = '';
			#if because of ssl on or off
			if(defined $ssloff)
			{
				#SSL off
				$sock->recv($line,$len);
			}
			else{
				#SSL on
				sysread($sock,$line,$len);
			}
            # append to $ret_line, in case we didn't get the whole word and are going round again
            $ret_line .= $line;
            my $got_len = length($line);
			
            if ($got_len < $len)
            {
                # we didn't get the whole word, so adjust length and try again
                $len -= $got_len;
            }
            else
            {
                # woot woot!  we got the required length
                last;
            }
        }
    }
    return $ret_line;
}

sub read_sentence {
    my ($word);
    my ($i) = 0;
    my (@reply);
    my($retval) = 0;
    while ($word = &read_word())
    {
            if ($word =~ /!done/)
            {
                $retval = 1;
            }
            elsif ($word =~ /!trap/)
            {
                $retval = 2;
            }
            elsif ($word =~ /!fatal/)
            {
                $retval = 3;
            }
        $reply[$i++] = $word;
        if ($debug > 2)
        {
            print "<<< $word\n"
        }
    }
    return ($retval,@reply);
}

######## PUBLIC FUNCTIONS ############

sub talk
{
    #my(@sentence) = shift;
    my($sentence_ref) = shift;
    my(@sentence) = @$sentence_ref;
    &write_sentence(\@sentence);
    my(@reply);
    my(@attrs);
    my($i) = 0;
    my($retval) = 0;
    while (($retval,@reply) = &read_sentence())
    {
        foreach my $line (@reply)
        {
            if ($line =~ /^=(\S+)=(.*)/s)
            {
                $attrs[$i]{$1} = $2;
            }
			
        }
        if ($retval > 0)
        {
            last;
        }
        $i++;
    }
    return ($retval, @attrs);
}

sub raw_talk
{
    my(@sentence) = @{(shift)};
    &write_sentence(\@sentence);
    my(@reply);
    my(@response);
    my($i) = 0;
    my($retval) = 0;
    while (($retval,@reply) = &read_sentence())
    {
        foreach my $line (@reply)
        {
            push(@response, $line);
        }
        if ($retval > 0)
        {
            last;
        }
    }
    return ($retval,@response);
}

sub login
{
    my($host) = shift;
    my($username) = shift;
    my($passwd) = shift;
	my($port) = shift;
	my($loginMode) = shift;
	$ssloff = shift;
	$sslvm = shift;# || default 0x01;
	
    if (!($sock = &mtik_connect($host,$port)))
    {
        return 0;
    }
    my(@command);
    my($retval,@results);
	
	if(defined $loginMode)
	{
		#Login method pre-v6.43
		push(@command,'/login');
		my($retval,@results) = talk(\@command);
		my($chal) = pack("H*",$results[0]{'ret'});
		my($md) = new Digest::MD5;
		$md->add(chr(0));
		$md->add($passwd);
		$md->add($chal);
		my($hexdigest) = $md->hexdigest;
		undef(@command);
		push(@command, '=name=' . $username);
		push(@command, '=response=00' . $hexdigest);
	}
	else
	{
		#Login method post-v6.43
		push(@command, '/login');
		push(@command, '=name=' . $username);
		push(@command, '=password=' . $passwd);
	}
	
    ($retval,@results) = &talk(\@command);
    if ($retval > 1)
    {
        $error_msg = $results[0]{'message'};
        return 0;
    }
    if ($debug > 0)
    {
        print "Logged in to $host as $username\n";
    }
    return 1;
}

sub logout
{
	if(defined $ssloff)
	{
		#SSL off
		close $sock;
	}
	else
	{
		#SSL on
		$sock->close(
		SSL_no_shutdown => 1, 
		SSL_ctx_free    => 1,    
		)
	}
}

sub get_by_key
{
    my($cmd) = shift;
    my($id) = shift || '.id';
    $error_msg = '';
    my(@command);
    @command = split / /, $cmd;
    my(%ids);
    my $count = 0;
    my($retval,@results) = &Mtik::talk(\@command);
    if ($retval > 1)
    {
        $error_msg = $results[0]{'message'};
        return %ids;
    }
    #print "\n" . Dumper(\@results) ."\n";
    foreach my $attrs (@results)
    {
        my $key = '';
        foreach my $attr (keys (%{$attrs}))
        {
            my $val = ${$attrs}{$attr};
            if ($attr eq $id)
            {
                $key = $val;
                #delete(${$attrs}{$attr});
            }
        }
        if ($key)
        {
            $ids{$key} = $attrs;
        }
	else {
		$ids{("n" . $count)} = $attrs;
	}
    }
    #print "\n" . Dumper(\%ids) ."\n";
    return %ids;
}

sub mtik_cmd
{
    my($cmd) = shift;
    my(%attrs) = %{(shift)};
    $error_msg = '';
    my(@command);
    push(@command,$cmd);
    foreach my $attr (keys (%attrs))
    {
        push(@command,'=' . $attr . '=' . $attrs{$attr});
    }
    my($retval,@results) = talk(\@command);
    if ($retval > 1)
    {
        $error_msg = $results[0]{'message'};
    }
    return ($retval,@results);
}

sub mtik_query
{
    my($cmd) = shift;
    my(%attrs) = %{(shift)};
	my(%queries) = %{(shift)};
    $error_msg = '';
    my(@command);
    push(@command,$cmd);
    foreach my $attr (keys (%attrs))
    {
        push(@command,'=' . $attr . '=' . $attrs{$attr});
    }
    foreach my $query (keys (%queries))
    {
        push(@command,'?' . $query . '=' . $queries{$query});
    }
    my($retval,@results) = talk(\@command);
    if ($retval > 1)
    {
        $error_msg = $results[0]{'message'};
    }
    return ($retval,@results);
}

1;
