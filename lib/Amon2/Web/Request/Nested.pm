package Amon2::Web::Request::Nested;
use 5.008005;
use strict;
use warnings;

our $VERSION = "0.01";

use HTTP::Headers;
use Carp ();
use Hash::MultiValue;
use HTTP::Body;

use Plack::Request::Upload;
use Stream::Buffered;
use URI;
use URI::Escape   ();
use Cookie::Baker ();
use HTTP::Entity::Parser;
use WWW::Form::UrlEncoded qw/parse_urlencoded build_urlencoded/;
use Data::NestedParams;

use Encode;

use Class::Tiny {
    cookies              => \&_build_cookies,
    headers              => \&_build_headers,
    _uri_base            => \&_build__uri_base,
    uri                  => \&_build_uri,
    base                 => \&_build_base,
    uploads              => \&_build_uploads,
    body_parameters      => \&_build_body_parameters,
    query_parameters     => \&_build_query_parameters,
    body_parameters_raw  => \&_build_body_parameters_raw,
    query_parameters_raw => \&_build_query_parameters_raw,
    _request_body        => \&_build__request_body,
    request_body_parser  => \&_build_request_body_parser,
};

sub new {
    my ( $class, $env ) = @_;
    Carp::croak(q{$env is required})
      unless defined $env && ref($env) eq 'HASH';

    bless { env => $env }, $class;
}

sub env { $_[0]->{env} }

# Accessors for Plack env keys.

sub address     { $_[0]->env->{REMOTE_ADDR} }
sub remote_host { $_[0]->env->{REMOTE_HOST} }
sub protocol    { $_[0]->env->{SERVER_PROTOCOL} }
sub method      { $_[0]->env->{REQUEST_METHOD} }
sub port        { $_[0]->env->{SERVER_PORT} }
sub user        { $_[0]->env->{REMOTE_USER} }
sub request_uri { $_[0]->env->{REQUEST_URI} }
sub path_info   { $_[0]->env->{PATH_INFO} }
sub path        { $_[0]->env->{PATH_INFO} || '/' }
sub script_name { $_[0]->env->{SCRIPT_NAME} }
sub scheme      { $_[0]->env->{'psgi.url_scheme'} }
sub secure      { $_[0]->scheme eq 'https' }
sub body        { $_[0]->env->{'psgi.input'} }
sub input       { $_[0]->env->{'psgi.input'} }

sub content_length { $_[0]->env->{CONTENT_LENGTH} }
sub content_type   { $_[0]->env->{CONTENT_TYPE} }

sub session         { $_[0]->env->{'psgix.session'} }
sub session_options { $_[0]->env->{'psgix.session.options'} }
sub logger          { $_[0]->env->{'psgix.logger'} }

sub _build_cookies {
    my $self = shift;
    Cookie::Baker::crush_cookie( $self->env->{HTTP_COOKIE} );
}

sub _build_headers {
    my $self = shift;
    Amon2::Web::Request::Util::make_headers( $self->env );
}

sub _build__uri_base {
    my $self = shift;
    Amon2::Web::Request::Util::make_base_uri( $self->env );
}

sub _build_uri {
    my $self = shift;

    my $base = $self->_uri_base;

    # We have to escape back PATH_INFO in case they include stuff like
    # ? or # so that the URI parser won't be tricked. However we should
    # preserve '/' since encoding them into %2f doesn't make sense.
    # This means when a request like /foo%2fbar comes in, we recognize
    # it as /foo/bar which is not ideal, but that's how the PSGI PATH_INFO
    # spec goes and we can't do anything about it. See PSGI::FAQ for details.

    # See RFC 3986 before modifying.
    my $path_escape_class = q{^/;:@&=A-Za-z0-9\$_.+!*'(),-};

    my $path = URI::Escape::uri_escape( $self->env->{PATH_INFO} || '', $path_escape_class );
    $path .= '?' . $self->env->{QUERY_STRING}
      if defined $self->env->{QUERY_STRING} && $self->env->{QUERY_STRING} ne '';

    $base =~ s!/$!! if $path =~ m!^/!;

    return URI->new( $base . $path )->canonical;
}

sub _build_base {
    my $self = shift;
    URI->new( $self->_uri_base )->canonical;
}

sub _build_request_body_parser {
    my $self = shift;

    my $parser = HTTP::Entity::Parser->new();
    $parser->register(
        'application/x-www-form-urlencoded',
        'HTTP::Entity::Parser::UrlEncoded'
    );
    $parser->register(
        'multipart/form-data',
        'HTTP::Entity::Parser::MultiPart'
    );
    $parser->register(
        'application/json',
        'HTTP::Entity::Parser::JSON'
    );
    $parser;
}

# [[], []]
sub _build__request_body {
    my $self = shift;

    if ( !$self->env->{CONTENT_TYPE} ) {
        return [
            [],
            []
        ];
    } else {
        my ( $params, $uploads ) = $self->request_body_parser->parse( $self->env );
        return [
            $params,
            do {
                my @uploads;
                my @x = @$uploads;
                while (my ($k, $v) = splice @$uploads, 0, 2) {
                    push @uploads, $k, Plack::Request::Upload->new(%$v);
                }
                \@uploads;
            },
        ];
    }
}

sub _build_uploads {
    my $self = shift;
    return expand_nested_params( $self->_request_body->[1] );
}

sub _build_body_parameters {
    my ($self) = @_;
    return expand_nested_params(
        $self->decode_parameters( @{$self->_request_body->[0]} )
    );
}

sub _build_query_parameters {
    my ($self) = @_;
    return expand_nested_params(
        $self->decode_parameters( parse_urlencoded( $self->env->{'QUERY_STRING'} ) )
    );
}

sub parameters {
    my $self = shift;

    return +{
        %{ $self->body_parameters },
        %{ $self->query_parameters },
    };
}

# User can override this method if user want to support non UTF-8 encoding.
sub decode_parameters {
    my $self = shift;
    my @decoded;
    while ( my ( $k, $v ) = splice @_, 0, 2 ) {
        push @decoded, Encode::decode_utf8($k), Encode::decode_utf8($v);
    }
    return \@decoded;
}

sub _build_body_parameters_raw {
    my $self = shift;
    return expand_nested_params( $self->_request_body->[0] );
}

sub _build_query_parameters_raw {
    my $self = shift;
    return expand_nested_params( [ parse_urlencoded( $self->env->{'QUERY_STRING'} ) ] );
}

sub parameters_raw {
    my $self = shift;

    +{
        %{ $self->query_parameters_raw },
        %{ $self->body_parameters_raw },
    };
}

package    # Hide from pause
  Amon2::Web::Request::Util;

# I want to port this part to Plack::Request::Util

sub make_headers {
    my $env = shift;

    return HTTP::Headers->new(
        map {
            ( my $field = $_ ) =~ s/^HTTPS?_//;
            ( $field => $env->{$_} );
          }
          grep { /^(?:HTTP|CONTENT)/i } keys %$env
    );
}

sub make_base_uri {
    my $env = shift;

    my $uri = ( $env->{'psgi.url_scheme'} || "http" ) .
      "://" .
      ( $env->{HTTP_HOST} || ( ( $env->{SERVER_NAME} || "" ) . ":" . ( $env->{SERVER_PORT} || 80 ) ) ) .
      ( $env->{SCRIPT_NAME} || '/' );

    return $uri;
}

1;
__END__

=encoding utf-8

=head1 NAME

Amon2::Web::Request::Nested - Web request object for Amon2

=head1 SYNOPSIS

    package MyApp::Web;
    use Amon2::Web::Request::Nested;

    sub create_request {
        my ($self, $env) = @_;
        Amon2::Web::Request->new($env, $self);
    }

=head1 DESCRIPTION

Amon2::Web::Request::Nested is web request object for Amon2 with following features.

=over 4

=item Support nested parameters like Rails

You can specify the nested query like following:

    <form method="post">
        <input type="text" name="x[y]" value="z">
        <input type="submit">
    </form>

Then you get the value as:

    {
        x => {
            y => 'z'
        }
    }

=item Cache uri

Plack::Request does not cache Plack::Request#uri. It hits the peformance issue if you call too much in the request handler.
This module cache the URI object.

(Then, you must clone object before modifying the object)

=back

=head1 LICENSE

Copyright (C) Tokuhiro Matsuno.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom@gmail.comE<gt>

=cut

