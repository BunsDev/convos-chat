package Convos::Core::Connection;

=head1 NAME

Convos::Core::Connection - A Convos connection base class

=head1 DESCRIPTION

L<Convos::Core::Connection> is a base class for L<Convos> connections.

See also L<Convos::Core::Connection::IRC>.

=cut

use Mojo::Base 'Mojo::EventEmitter';
use Mojo::URL;
use Convos::Core::Room;
use constant DEBUG => $ENV{CONVOS_DEBUG} || 0;

=head1 EVENTS

=head2 log

  $self->on(log => sub { my ($self, $level, $message) = @_; });

Emitted when a connection want L</log> a message. C<$level> has the same values
as the log levels defined in L<Mojo::Log>.

These messages could be stored to a persistent storage.

=head2 room

  $self->on(room => sub { my ($self, $room, $changed) = @_; });

Emitted when a L<$room|Convos::Core::Room> change properties. C<$changed> is
a hash-ref with the changed attributes.

=head1 ATTRIBUTES

L<Convos::Core::Connection> inherits all attributes from L<Mojo::Base> and implements
the following new ones.

=head2 name

  $str = $self->name;

Holds the name of the connection.

=head2 rooms

  $array_ref = $self->rooms;
  $self = $self->rooms(["#convos", "#channel with-key"]);

Holds a list of rooms / channel names.

=head2 url

  $url = $self->url;

Holds a L<Mojo::URL> object which describes where to connect to. This
attribute is read-only.

=head2 user

  $user = $self->user;

Holds a L<Convos::Core::User> object that owns this connection.

=cut

sub name { shift->{name} or die 'name is required in constructor' }
has rooms => sub { [] };

sub url {
  return $_[0]->{url} if ref $_[0]->{url};
  return $_[0]->{url} = Mojo::URL->new($_[0]->{url} || '');
}

has user => sub { die 'user is required' };

=head1 METHODS

L<Convos::Core::Connection> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 connect

  $self = $self->connect(sub { my ($self, $err) = @_ });

Used to connect to L</url>. Meant to be overloaded in a subclass.

=cut

sub connect { my ($self, $cb) = (shift, pop); $self->tap($cb, 'Method "connect" not implemented.'); }

=head2 join_room

  $self = $self->join_room("#some_channel", sub { my ($self, $err) = @_; });

Used to join a room. See also L</room> event.

=cut

sub join_room { my ($self, $cb) = (shift, pop); $self->tap($cb, 'Method "join_room" not implemented.'); }

=head2 load

  $self = $self->load(sub { my ($self, $err) = @_; });

Will load L</ATTRIBUTES> from persistent storage.
See L<Convos::Core::Backend/load_object> for details.

=cut

sub load {
  my $self = shift;
  $self->user->core->backend->load_object($self, @_);
  $self;
}

=head2 log

  $self = $self->log($level => $format, @args);

This method will emit a L</log> event.

=cut

sub log {
  my ($self, $level, $format, @args) = @_;
  my $message = @args ? sprintf $format, map { $_ // '' } @args : $format;

  $self->emit(log => $level => $message);
}

=head2 room

  $room = $self->room($id);            # get
  $room = $self->room($id => \%attrs); # create/update

Will return a L<Convos::Core::Room> object, identified by C<$id>.

=cut

sub room {
  my ($self, $id, $attr) = @_;

  if ($attr) {
    my $room = $self->{room}{$id} ||= do {
      my $room = Convos::Core::Room->new(connection => $self, id => $id);
      Scalar::Util::weaken($room->{connection});
      warn "[Convos::Core::User] Emit room: id=$id\n" if DEBUG;
      $self->user->core->backend->emit(room => $room);
      $room;
    };
    $room->{$_} = $attr->{$_} for keys %$attr;
    return $room;
  }
  else {
    return $self->{room}{$id} || Convos::Core::Room->new(id => $id);
  }
}

=head2 room_list

  $self = $self->room_list(sub { my ($self, $err, $list) = @_; });

Used to retrieve a list of L<Convos::Core::Room> objects for the given
connection.

=cut

sub room_list { my ($self, $cb) = (shift, pop); $self->tap($cb, 'Method "room_list" not implemented.', []); }

=head2 save

  $self = $self->save(sub { my ($self, $err) = @_; });

Will save L</ATTRIBUTES> to persistent storage.
See L<Convos::Core::Backend/save_object> for details.

=cut

sub save {
  my $self = shift;
  $self->user->core->backend->save_object($self, @_);
  $self;
}

=head2 send

  $self = $self->send($target => $message, sub { my ($self, $err) = @_; });

Used to send a C<$message> to C<$target>. C<$message> is a plain string and
C<$target> can be a user or room name.

Meant to be overloaded in a subclass.

=cut

sub send { my ($self, $cb) = (shift, pop); $self->tap($cb, 'Method "send" not implemented.') }

=head2 state

  $self = $self->state($str);
  $str = $self->state;

Holds the state of this object. Supported states are "disconnected",
"connected" or "connecting" (default). "connecting" means that the object is
in the process of connecting or that it want to connect.

=cut

sub state {
  my ($self, $state) = @_;
  return $self->{state} ||= 'connecting' unless $state;
  die "Invalid state: $state" unless grep { $state eq $_ } qw( connected connecting disconnected );
  $self->{state} = $state;
  $self;
}

=head2 topic

  $self = $self->topic($room, sub { my ($self, $err, $topic) = @_; });
  $self = $self->topic($room => $topic, sub { my ($self, $err) = @_; });

Used to retrieve or set topic for a room.

=cut

sub topic { my ($self, $cb) = (shift, pop); $self->tap($cb, 'Method "topic" not implemented.') }

sub _path { join '/', $_[0]->user->_path, join '-', ref($_[0]) =~ /(\w+)$/, $_[0]->name }

sub _userinfo {
  my $self = shift;
  my @userinfo = split /:/, $self->url->userinfo // '';
  $userinfo[0] ||= $self->user->email =~ /([^@]+)/ ? $1 : '';
  $userinfo[1] ||= undef;
  return \@userinfo;
}

sub TO_JSON {
  my ($self, $persist) = @_;
  $self->{state} ||= 'connecting';
  my $json = {map { ($_, $self->$_) } qw( name rooms state url )};
  $json->{state} = 'connecting' if $persist and $json->{state} eq 'connected';
  $json;
}

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;