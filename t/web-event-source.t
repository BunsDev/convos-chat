BEGIN { $ENV{CONVOS_CONNECT_TIMER} = 0.1 }
use t::Helper;

my $t = t::Helper->t;

$t->get_ok('/events/event-source')->content_is(qq(event:error\ndata:{"message":"Need to log in first."}\n\n));

my $user = $t->app->core->user('superman@example.com', {avatar => 'avatar@example.com'})->set_password('s3cret')->save;
$t->post_ok('/api/user/login', json => {email => 'superman@example.com', password => 's3cret'})->status_is(200);
$t->post_ok('/api/connections', json => {state => 'connect', url => 'irc://localhost:3123'})->status_is(200);

my $tx = $t->ua->build_tx(GET => '/events/event-source');
my $buffer = '';
$tx->res->content->unsubscribe('read')->on(
  read => sub {
    my ($content, $chunk) = @_;
    $buffer .= $chunk;
    $user->connection('irc-localhost')->state('disconnected');    # change from connecting to disconnected
    $tx->res->error({message => 'Interrupted'}) if $buffer =~ /event:state\n.*\}/s;
  }
);
$t->ua->start($tx);
is $tx->res->code, 200, '200 OK';
is $tx->res->headers->content_type, 'text/event-stream', 'Content-Type: text/event-stream';
like $buffer, qr/event:state\ndata:.*"state":"connecting"/, 'got state event';

done_testing;
