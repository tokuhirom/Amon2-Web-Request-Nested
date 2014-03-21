use strict;
use warnings;
use utf8;
use Test::More;
use Amon2::Web::Request::Nested;

subtest 'basic json request', sub {
    my $req = make_request(
        'application/json; charset=utf-8',
        '{"a":["b","c"]}',
    );
    is_deeply $req->parameters->{'a'}, ['b', 'c'];
};

subtest 'multibyte chars', sub {
    my $req = make_request(
        'application/json; charset=utf-8',
        '{"a":"\u3042"}',
    );
    is_deeply $req->parameters->{'a'}, "\x{3042}";
    ok !Encode::is_utf8($req->parameters_raw->{'a'});
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
