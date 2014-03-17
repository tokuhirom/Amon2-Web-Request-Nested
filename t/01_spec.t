use strict;
use warnings;
use utf8;
use Test::More;
use Amon2::Web::Request::Nested;

sub describe { goto \&subtest }
sub should   { goto \&subtest }
sub context  { goto \&subtest }

sub req { Amon2::Web::Request::Nested->new(@_) }

describe 'Amon2::Web::Request::Nested', sub {
    should 'parse cookies correctly', sub {
        my $req = Amon2::Web::Request::Nested->new(
            +{
                HTTP_COOKIE => 'foo=val',
            }
        );
        is_deeply $req->cookies, {foo => 'val'};
    };

    should 'return REMOTE_ADDR', sub {
        my $req = Amon2::Web::Request::Nested->new(
            +{ REMOTE_ADDR => '127.0.0.1' }
        );
        is $req->address, '127.0.0.1';
    };

    should 'make HTTP::Headers correctly', sub {
        my $headers = req(
            +{
                HTTP_COOKIE => 'foo=val',
                CONTENT_LENGTH => 4
            }
        )->headers;
        is $headers->content_length, 4;
        is $headers->header('Cookie'), 'foo=val';
    };

    should 'make URI correctly', sub {
        my @cases = (
            +{
                HTTP_HOST => 'example.com',
                SCRIPT_NAME => '/'
            },
            'http://example.com/',

            +{
                SERVER_NAME => 'localhost',
                SCRIPT_NAME => '/'
            },
            'http://localhost/',

            +{
                QUERY_STRING => 'h=q',
                HTTP_HOST => 'example.com',
                SCRIPT_NAME => '/foo'
            },
            'http://example.com/foo?h=q',
        );
        while (my ($input, $expected) = splice @cases, 0, 2) {
            is req( $input )->uri->as_string, $expected;
        }
    };

    should 'make uploads correctly', sub {
        my $content = <<'...';
--BOUNDARY
Content-Disposition: form-data; name="xxx"
Content-Type: text/plain

yyy
--BOUNDARY
Content-Disposition: form-data; name="yappo"; filename="osawa.txt"
Content-Type: text/plain

SHOGUN
--BOUNDARY--
...
        $content =~ s/\r\n/\n/g;
        $content =~ s/\n/\r\n/g;

        my $req = make_request('multipart/form-data; boundary=BOUNDARY', $content);
        ok not exists $req->uploads->{xxx};
        is slurp($req->uploads->{yappo}->path), 'SHOGUN';
    };

    should 'make nested uploads correctly', sub {
        my $content = <<'...';
--BOUNDARY
Content-Disposition: form-data; name="xxx"
Content-Type: text/plain

yyy
--BOUNDARY
Content-Disposition: form-data; name="yappo[]"; filename="suspended.txt"
Content-Type: text/plain

SEII
--BOUNDARY
Content-Disposition: form-data; name="yappo[]"; filename="osawa.txt"
Content-Type: text/plain

SHOGUN
--BOUNDARY--
...
        $content =~ s/\r\n/\n/g;
        $content =~ s/\n/\r\n/g;

        my $req = make_request('multipart/form-data; boundary=BOUNDARY', $content);
        is $req->body_parameters->{xxx}, 'yyy';
        ok not exists $req->uploads->{xxx};
        isa_ok $req->uploads->{yappo}, 'ARRAY';
        is 0+@{$req->uploads->{yappo}}, 2;
        is slurp($req->uploads->{yappo}[0]->path), 'SEII';
        is slurp($req->uploads->{yappo}[1]->path), 'SHOGUN';
    };

    should 'parse body parameters with decoding', sub {
        context 'single multibyte char', sub {
            my $req = make_request('application/x-www-form-urlencoded', 'x=%E3%81%82');
            is $req->body_parameters->{x}, 'あ';
        };

        context 'nested', sub {
            my $req = make_request('application/x-www-form-urlencoded', 'x[]=%E3%81%82&x[]=%E3%81%84');
            is_deeply $req->body_parameters->{x}, ['あ', 'い'];
        };
    };

    should 'parse body parameters without decoding', sub {
        context 'single multibyte char', sub {
            my $req = make_request('application/x-www-form-urlencoded', 'x=%E3%81%82');
            is $req->body_parameters_raw->{x}, "\343\201\202";
        };

        context 'nested', sub {
            my $req = make_request('application/x-www-form-urlencoded', 'x[]=%E3%81%82&x[]=%E3%81%84');
            is_deeply $req->body_parameters_raw->{x}, ["\343\201\202", "\343\201\204"];
        };
    };

    should 'parse query parameters with decoding correctly', sub {
        context 'single multibyte char', sub {
            my $req = req(+{ QUERY_STRING => 'x=%E3%81%82' });
            is $req->query_parameters->{x}, 'あ';
        };

        context 'nested', sub {
            my $req = req(+{ QUERY_STRING =>  'x[]=%E3%81%82&x[]=%E3%81%84'});
            is_deeply $req->query_parameters->{x}, ['あ', 'い'];
        };
    };

    should 'parse query parameters without decoding correctly', sub {
        context 'single multibyte char', sub {
            my $req = req(+{ QUERY_STRING => 'x=%E3%81%82' });
            is $req->query_parameters_raw->{x}, "\343\201\202";
        };

        context 'nested', sub {
            my $req = req(+{ QUERY_STRING =>  'x[]=%E3%81%82&x[]=%E3%81%84'});
            is_deeply $req->query_parameters_raw->{x}, ["\343\201\202", "\343\201\204"];
        };
    };

    should 'parse merged parameters correctly', sub {
        my $req = make_request('application/x-www-form-urlencoded', 'x[]=%E3%81%82&x[]=%E3%81%84', +{ QUERY_STRING => 'y=%E3%81%86' });
        is_deeply $req->parameters, {
            x => ['あ', 'い'],
            y => 'う',
        };
        is_deeply $req->parameters_raw, {
            x => ["\343\201\202", "\343\201\204"],
            y => "\343\201\206",
        };
    };
};

describe 'Amon2::Web::Request::Util', sub {
    should 'make base URI correctly', sub {
        my @cases = (
            +{
                HTTP_HOST => 'example.com',
                SCRIPT_NAME => '/'
            },
            'http://example.com/',
            +{
                'psgi.url_scheme' => 'https',
                HTTP_HOST => 'example.com',
                SCRIPT_NAME => '/'
            },
            'https://example.com/',
            +{
                SERVER_NAME => 'localhost',
                SCRIPT_NAME => '/'
            },
            'http://localhost:80/',
            +{
                SERVER_NAME => 'localhost',
                SERVER_PORT => 8080,
                SCRIPT_NAME => '/'
            },
            'http://localhost:8080/',
        );
        while (my ($input, $expected) = splice @cases, 0, 2) {
            is Amon2::Web::Request::Util::make_base_uri( $input ), $expected;
        }
    };
};

done_testing;

sub make_request {
    my ($content_type, $content, $env) = @_;
    $env ||= +{};

    open my $input, '<', \$content;
    my $req = Amon2::Web::Request::Nested->new(
        +{
            %$env,
            'psgi.input'   => $input,
            CONTENT_TYPE   => $content_type,
            CONTENT_LENGTH => length($content),
        },
    );
    return $req;
}

sub slurp {
    my $fname = shift;
    open my $fh, '<', $fname
        or Carp::croak("Can't open '$fname' for reading: '$!'");
    scalar(do { local $/; <$fh> })
}
