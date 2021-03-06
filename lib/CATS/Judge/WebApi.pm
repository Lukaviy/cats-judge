package CATS::Judge::WebApi;

use strict;
use warnings;

use LWP::UserAgent;
use JSON::XS;
use HTTP::Request::Common;
use CATS::DevEnv;
use CATS::JudgeDB;

use base qw(CATS::Judge::Base);

sub new_from_cfg {
    my ($class, $cfg) = @_;
    $class->SUPER::new(name => $cfg->name, password => $cfg->cats_password, cats_url => $cfg->cats_url);
}

sub init {
    my ($self) = @_;

    $self->{agent} = LWP::UserAgent->new(requests_redirectable => [ qw(GET POST) ]);
}

sub get_json {
    my ($self, $params) = @_;

    push @$params, 'json', 1;
    my $request = $self->{agent}->request(POST "$self->{cats_url}/", $params);
    die "Error: $request->{_rc} '$request->{_msg}'" unless $request->{_rc} == 200;
    decode_json($request->{_content});
}

sub auth {
    my ($self) = @_;

    my $response = $self->get_json([
        f => 'login',
        login => $self->{name},
        passwd => $self->{password},
    ]);
    die "Incorrect login and password" if $response->{status} eq 'error';
    $self->{sid} = $response->{sid};

    $response = $self->get_json([
        f => 'get_judge_id',
        sid => $self->{sid},
    ]);
    die "get_judge_id: $response->{error}" if $response->{error};
    $self->{id} = $response->{id};
}

sub is_locked { $_[0]->{lock_counter} }

sub update_dev_env {
    my ($self) = @_;

    my $response = $self->get_json([
        f => 'api_judge_get_des',
        sid => $self->{sid},
    ]);

    die "update_dev_env: $response->{error}" if $response->{error};

    $self->{dev_env} = CATS::DevEnv->new($response);
}

sub get_problem {
    my ($self, $pid) = @_;

    my $response = $self->get_json([
        f => 'api_judge_get_problem',
        pid => $pid,
        sid => $self->{sid},
    ]);

    die "get_problem: $response->{error}" if $response->{error};

    $response->{problem};
}

sub get_problem_sources {
    my ($self, $pid) = @_;

    my $response = $self->get_json([
        f => 'api_judge_get_problem_sources',
        pid => $pid,
        sid => $self->{sid},
    ]);

    die "get_problem_sources: $response->{error}" if $response->{error};

    $response->{sources};
}

sub get_problem_tests {
    my ($self, $pid) = @_;

    my $response = $self->get_json([
        f => 'api_judge_get_problem_tests',
        pid => $pid,
        sid => $self->{sid},
    ]);

    die "get_problem_tests: $response->{error}" if $response->{error};

    $response->{tests};
}

sub is_problem_uptodate {
    my ($self, $pid, $date) = @_;

    my $response = $self->get_json([
        f => 'api_judge_is_problem_uptodate',
        pid => $pid,
        date => $date,
        sid => $self->{sid},
    ]);

    die "is_problem_uptodate: $response->{error}" if $response->{error};

    $response->{uptodate};
}

sub save_log_dump {
    my ($self, $req, $dump) = @_;

    my $response = $self->get_json([
        f => 'api_judge_save_log_dump',
        req_id => $req->{id},
        dump => $dump,
        sid => $self->{sid},
    ]);

    die "save_log_dump: $response->{error}" if $response->{error};
}

sub set_request_state {
    my ($self, $req, $state, %p) = @_;

    my $response = $self->get_json([
        f => 'api_judge_set_request_state',
        req_id => $req->{id},
        state => $state,
        problem_id => $p{problem_id},
        contest_id => $p{contest_id},
        failed_test => $p{failed_test},
        sid => $self->{sid},
    ]);

    die "set_request_state: $response->{error}" if $response->{error};
}

sub select_request {
    my ($self) = @_;

    my $response = $self->get_json([
        f => 'api_judge_select_request',
        sid => $self->{sid},
        de_version => $self->{dev_env}->version,
        CATS::JudgeDB::get_de_bitfields_hash(@{$self->{de_bitmap}}),
    ]);

    if ($response->{error}) {
        if ($response->{error} eq $cats::es_old_de_version) {
            warn 'updating des list';
            $self->update_dev_env();
            $self->update_de_bitmap();
            return;
        } else {
            die "select_request: $response->{error}"
        }
    }

    $self->{lock_counter} = $response->{lock_counter};
    $self->{was_pinged} = $response->{was_pinged};
    $response->{request};
}

sub delete_req_details {
    my ($self, $req_id) = @_;

    my $response = $self->get_json([
        f => 'api_judge_delete_req_details',
        req_id => $req_id,
        sid => $self->{sid},
    ]);

    die "delete_req_details: $response->{error}" if $response->{error};
}

sub insert_req_details {
    my ($self, $p) = @_;

    my $response = $self->get_json([
        f => 'api_judge_insert_req_details',
        params => encode_json($p),
        sid => $self->{sid},
    ]);

    die "insert_req_details: $response->{error}" if $response->{error};
}

sub save_input_test_data {
    my ($self, $problem_id, $test_rank, $input, $input_size) = @_;

    my $response = $self->get_json([
        f => 'api_judge_save_input_test_data',
        problem_id => $problem_id,
        test_rank => $test_rank,
        input => $input,
        input_size => $input_size,
        sid => $self->{sid},
    ]);

    die "save_input_test_data: $response->{error}" if $response->{error};
}

sub save_answer_test_data {
    my ($self, $problem_id, $test_rank, $answer, $answer_size) = @_;

    my $response = $self->get_json([
        f => 'api_judge_save_answer_test_data',
        problem_id => $problem_id,
        test_rank => $test_rank,
        answer => $answer,
        answer_size => $answer_size,
        sid => $self->{sid},
    ]);

    die "save_answer_test_data: $response->{error}" if $response->{error};
}

sub get_testset {
    my ($self, $req_id, $update) = @_;

    my $response = $self->get_json([
        f => 'api_judge_get_testset',
        req_id => $req_id,
        update => $update,
        sid => $self->{sid},
    ]);

    die "get_testset: $response->{error}" if $response->{error};

    %{$response->{testset}};
}

1;
