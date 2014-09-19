#
#
# usage:
# puppet apply -vd --modulepath=/network/srv/developer/puppet/modules --graph --graphdir ./graph concat_test.pp
# ./upstream_puppet apply -vd --modulepath=/network/srv/developer/puppet/modules concat_test.pp
#

#import "common"

#import "manifests/defines/*.pp"

filebucket { 
    server:
        server => $::puppetserver
}

# disable clientbuckets globally - we do not want to keep copies of files that
# puppet overwrites
File { backup => false }

file {
    '/tmp/include_file':
        mode => 0666,
        content => "concat2_2 include\n";
}

define entity($ensure=present, $parent, $order, $content) {
    concat_fragment {
        $name:
            parent => $parent,
            order => $order,
            content => $content;
    }
}

class deep_down {
    entity {
        'concat2_1_3':
            parent => 'concat2_1',
            order => 3,
            content => "concat2_1_3\n";
        'concat2_1_2':
            parent => 'concat2_1',
            order => 2,
            content => "concat2_1_2\n";
        'concat2_1_1':
            parent => 'concat2_1',
            order => 1,
            content => "concat2_1_1\n";
    }
}

class all_files {
    concat_file {
        '/tmp/concat_test': 
            path => '/tmp/concat_test_redir',
            mode => 0666;
        '/tmp/concat_test2': 
            mode => 0666;
#        '/tmp/concat_test_perms':
 #           mode => 0666, owner => 0, group => nogroup;
    }
}

class basic_two inherits all_files {
    concat_fragment {
        '2_concat1':
            target => '/tmp/concat_test2',
            order => 1,
            content => "concat1\n";
        '2_concat2':
            target => '/tmp/concat_test2',
            order => 2,
            content => "concat2\n";
        '2_concat3':
            target => '/tmp/concat_test2',
            order => 3,
            content => "concat3\n";
    }
}

class basic_one inherits all_files {
    
    entity {
        'concat2_1':
            parent => 'concat2',
            order => 1,
            content => "concat2_1\n";
        'concat2_1b':
            parent => 'concat2',
            order => 1,
            content => "concat2_1b\n";
        'concat2_3a':
            parent => 'concat2',
            order => 3,
            content => "concat2_3a\n";
        'concat2_3b':
            parent => 'concat2',
            order => 3,
            content => "concat2_3b\n";
    }
    concat_fragment {
        'concat2_2':
            parent => 'concat2',
            order => 2,
            source => '/tmp/include_file';

        'concat1':
            target => '/tmp/concat_test',
            order => 1,
            content => "concat1\n";
        'concat2':
            target => '/tmp/concat_test',
            order => 2,
            content => "concat2\n";
        'concat3':
            target => '/tmp/concat_test',
            order => 3,
            content => "concat3\n";
    }
}

include basic_one
#include basic_two
include deep_down
