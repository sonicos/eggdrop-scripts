# Script for integrating Stashboard (http://www.stashboard.org/) and an IRC Eggdrop
# Portions of this script came from https://github.com/horgh/eggdrop-scripts
# I used the google script as a baseline
#
# Created 2013-04-15
#
# License: Public domain
#
# Requires Tcl 8.5+
# Requires tcllib for json
#

package require http
package require json
package require htmlparse

namespace eval stashboard {
  #variable output_cmd "cd::putnow"
	variable output_cmd "putserv"

	# Not enforced for API queries
	variable useragent "Lynx/2.8.8dev.2 libwww-FM/2.14 SSL-MM/1.4.1"

	variable api_url "http://stashboard.example.com/admin/api/v1/"

	variable api_referer "http://www.egghelp.org"

	bind pub	-|- "!servicelist" stashboard::servicelist     # Get list of known service objects
	bind pub	-|- "!statuslist" stashboard::statuslist       # Get list of known status types
	bind pub	-|- "!getallservices" stashboard::statusall    # Get current status of all services
	bind pub	-|- "!getservice" stashboard::status           # Get status of named service
	bind pub	-|- "!updateservice" stashboard::updateservice # Update named service with status message


	setudef flag stashboard
}






# Output for results from api query
proc google::output {chan url title content} {
	regsub -all -- {(?:<b>|</b>)} $title "\002" title
	regsub -all -- {<.*?>} $title "" title
	set output "$title @ $url"
	$google::output_cmd "PRIVMSG $chan :[htmlparse::mapEscapes $output]"
}

# Return results from API query of $url
proc stashboard::api_fetch {terms url} {
	set query [http::formatQuery v "1.0" q $terms safe off]
	set headers [list Referer $stashboard::api_referer]

	set token [http::geturl ${url}?${query} -headers $headers -method GET]
	set data [http::data $token]
	set ncode [http::ncode $token]
	http::cleanup $token

	# debug
	#set fid [open "g-debug.txt" w]
	#fconfigure $fid -translation binary -encoding binary
	#puts $fid $data
	#close $fid

	if {$ncode != 200} {
		error "HTTP query failed: $ncode"
	}

	return [json::json2dict $data]
}

# API Post
proc stashboard::api_post {terms url} {
	set query [http::formatQuery v "1.0" q $terms safe off]
	set headers [list Referer $google::api_referer]

	set token [http::geturl ${url}?${query} -headers $headers -method GET]
	set data [http::data $token]
	set ncode [http::ncode $token]
	http::cleanup $token

	# debug
	#set fid [open "g-debug.txt" w]
	#fconfigure $fid -translation binary -encoding binary
	#puts $fid $data
	#close $fid

	if {$ncode != 200} {
		error "HTTP query failed: $ncode"
	}

	return [json::json2dict $data]
}

# Validate input and then return list of results
proc google::api_validate {argv url} {
	if {[string length $argv] == 0} {
		error "Please supply search terms."
	}

	if {[catch {google::api_fetch $argv $url} data]} {
		error "Error fetching results: $data."
	}

	set response [dict get $data responseData]
	set results [dict get $response results]

	if {[llength $results] == 0} {
		error "No results."
	}

	return $results
}

# Query api
proc google::api_handler {chan argv url {num {}}} {
	if {[catch {google::api_validate $argv $url} results]} {
		$google::output_cmd "PRIVMSG $chan :$results"
		return
	}

	foreach result $results {
		if {$num != "" && [incr count] > $num} {
			return
		}
		dict with result {
			# $language holds lang in news results, doesn't exist in web results
			if {![info exists language] || $language == "en"} {
				google::output $chan $unescapedUrl $title $content
			}
		}
	}
}

# Regular API search
proc google::search {nick uhost hand chan argv} {
	if {![channel get $chan google]} { return }

	google::api_handler $chan $argv ${google::api_url}web
}



# Update Stashboard
proc stashboard::updateservice {nick uhost hand chan argv} {
	if {![channel get $chan stashboard]} { return }
	if {![isop $nick $chan]} {
		$google::output_cmd "PRIVMSG $chan :$nick - You must be a channel operator."
		return
	}

	google::api_handler $chan $argv ${google::api_url}images
}
