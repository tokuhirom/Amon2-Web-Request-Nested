requires 'perl', '5.008001';

requires 'Class::Tiny';
requires 'Cookie::Baker', '0.03';
requires 'Encode';
requires 'HTTP::Body';
requires 'HTTP::Entity::Parser';
requires 'HTTP::Headers';
requires 'Hash::MultiValue';
requires 'Plack::Request::Upload';
requires 'Stream::Buffered';
requires 'URI';
requires 'URI::Escape';
requires 'WWW::Form::UrlEncoded';

on 'test' => sub {
    requires 'Test::More', '0.98';
};

