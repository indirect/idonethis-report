#!/usr/bin/env ruby

require 'rdoc'
include RDoc::Text

require 'bundler/inline'

gemfile do
  source "https://rubygems.org"
  gem 'idonethis'
  gem 'netrc'
  gem 'terminal-table'
end

whole_team = !ARGV.delete('--whole-team').nil?
month = ARGV.shift || Date.today.strftime('%Y-%m')
user, token = Netrc.read['idonethis.com']

if user.nil? || token.nil?
  warn "You need to store a user and token in your ~/.netrc file. Here's an example:"
  warn <<~NETRC
    machine idonethis.com
      login <your iDoneThis email/username>
      password <token from https://idonethis.com/api/token/>
  NETRC
  abort
end

client = IDoneThis::Client.new(token)
request = {
            done_date_after: "#{month}-01",
            done_date_before: "#{month.succ}-01",
            page_size: 100,
            page: 0,
          }
request[:owner] = user unless whole_team
dones = []
while
  request[:page] += 1
  response = client.dones(request)
  dones += response['results']
  break unless response['next']
end
dones = dones.group_by {|d| d['owner'] }
dones.each_value do |v|
  v.map! do |done|
    raw_text   = wrap(done['raw_text'], 100)
    time, desc = raw_text.split(' ', 2)
    desc.gsub!(/&amp;/, '&')
    desc.gsub!(/&(quot|rquo|lquo);/, '"')
    minutes = if time.end_with?('h')
      time[0..-2].to_f * 60
    else
      time[0..-2].to_f
    end.to_i
    hours = minutes./(60.0).round(2)
    [done['done_date'], hours, desc]
  end
  v.sort_by!(&:first)
end

dones.each do |owner, rows|
  total_hours = rows.reduce(0) {|s, d| s + d[1] }

  rows.each{|r| r[1] = "%0.2f" % r[1] }
  table = Terminal::Table.new headings: %w(Date Hours Description), rows: rows
  table.title = owner
  table.add_separator
  table.add_row [month, "%0.2f" % total_hours, "$#{"%0.2f" % (total_hours * 150)}"]

  puts table
  puts
  puts
end
