#!/usr/bin/perl

# Simple program to monitor http://gggtracker.com/activity.json and post new updates
# to the #ggg-tracker channel on the /r/pathofexile Discord
#
# 1. Polls gggtracker for activity
# 2. Compares against internal database of posts
# 3. If there are new posts in activity then formats and sends them
#
# There isn't much in the way of error handling in here at the moment.
#
# Requires:
#
# cpanm Tie::LevelDB JSON::XS LWP::Curl File::Slurp HTML::StripTags HTML::Entities WebService::Slack::IncomingWebHook
# (leveldb must be installed separately)
#
# Webhook information is stored in a file called "webhook.json" as follows:
# {
#   "url" : "webhook_url_here"
# }
# Note that I'm lazy and use the slack compat webhook, so add /slack to it
# if needed

$| = 1;
use File::Slurp;
use JSON::XS;
use Tie::LevelDB;
use LWP::Curl;
use HTML::Entities;
use WebService::Slack::IncomingWebHook;
use HTML::StripTags qw(strip_tags);

my $lwpcurl = LWP::Curl->new();

# ====================================================
# On startup:
#
# 1. Read in webhook.json file

$webhookConfig = decode_json(read_file('webhook.json'));
unless ($webhookConfig->{url}) {
  die "ERROR: url was not properly read from webhook.json!\n";
}
my $gohook = WebService::Slack::IncomingWebHook->new(
  webhook_url => $webhookConfig->{url},
  channel     => "ggg-tracker"
);

# 2. Tie to leveldb
my $db = new Tie::LevelDB::DB("gggtracker.db");

# ====================================================
# Start an infinite loop to check for activity
# sleep 60s between loops at the end

while ($loop < 1) {
  # Get the activity.json file and parse it
  my $activity = decode_json($lwpcurl->get('http://gggtracker.com/activity.json'));

  # Iterate through the activity array
  foreach $post (@{$activity->{activity}}) {
    my $dbid;
    # Create a local id based on the specific post type and links
    if ($post->{type} eq "forum_post") {
      $dbid = $post->{data}->{thread_id}.".".$post->{data}->{id};
    } elsif (($post->{type} eq "reddit_post") || ($post->{type} eq "reddit_comment")) {
      $dbid = $post->{data}->{post_id}.".".$post->{data}->{id};
    } else {
      next;
    }
    
    # Check to see if we already have this id in the database
    if ($db->Get("$dbid")) {
      print localtime()." $dbid is already in database, ignoring.\n";
    } else {
      print localtime()." $dbid is a new post, processing.\n";
      # Format a message
      my $message;

      if ($post->{type} eq "forum_post") {
        my $url = "https://www.pathofexile.com/forum/view-thread/".$post->{data}->{thread_id}."/page/".$post->{data}->{page_number}."#".$post->{data}->{id};
        chomp(my $summary = decode_entities(strip_tags(substr($post->{data}->{body_html}, 0, 256))));
        $summary .= "...(more)" if (length(decode_entities(strip_tags($post->{data}->{body_html}))) > 255);
        $message = "Forum Post by $post->{data}->{poster}: $url \`\`\`$summary\`\`\`";
      } elsif ($post->{type} eq "reddit_comment") {
        my $url = "https://www.reddit.com/r/pathofexile/comments/".$post->{data}->{post_id}."/-/".$post->{data}->{id}."/\?context=1";
        chomp(my $summary = decode_entities(strip_tags(substr($post->{data}->{body_html}, 0, 256))));
        $summary .= "...(more)" if (length(decode_entities(strip_tags($post->{data}->{body_html}))) > 255);
        $message = "Reddit Comment by /u/$post->{data}->{author}: $url \`\`\`$summary\`\`\`";
      } elsif ($post->{type} eq "reddit_post") {
        my $url = "https://www.reddit.com".$post->{data}->{permalink};
        $message = "Reddit Post by /u/$post->{data}->{author}: $url";
      } else {
        print localtime()." Unknown post type! ".$post->{type}."\n";
      }

      print localtime()." $message\n--\n";
      # Post message to discord
      $gohook->post(
        text => $message
      );      
      # Prevent spam
      sleep 2;

      # Store in DB
      $db->Put("$dbid","1");
    }

  }




  sleep 60;
}

