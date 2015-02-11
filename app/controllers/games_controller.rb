class GamesController < ApplicationController
    
require 'nokogiri'
require 'open-uri'
require 'ostruct'
 
 
class SportsScraper
  BASE_URL = "http://www.sportsbookreview.com/betting-odds/"
  SPORT = "nba-basketball/"
  def collect_lines(lines)
    lines_collect = []
    lines.each do |lines|
      lines = lines.text rescue lines
      lines.scan(/[\d\-.]+/) do |x|
        lines_collect << x
      end
    end
    lines_collect
  end
 
  def parse_url url
    f = open(url).read
    f.gsub!("½", ".5")
    Nokogiri::HTML(f, nil, "UTF-8")
  end
 
  def parse_test_data
    require './html_inprogress_games'
    f = HTMLSource.html_source
    f.gsub!("½", ".5")
    Nokogiri::HTML(f, nil, "UTF-8")
  end
 
  def get_scores html
    results = {}
    games = []
    scores = html.xpath('.//*[@class="score"]').each do |node|
      game_id = node.attribute("id").value.gsub(/[^\d]*/, "")
      games << game_id
    end
 
    scores_array = html.css(".score").css(".period").collect do |x| x.text.strip end
    total_array = html.css(".score").css(".total").collect do |x| x.text.strip end
 
    scores_array.each_slice(8).with_index do |scores, i|
      results[games[i]] = OpenStruct.new
      results[games[i]].away_scores = scores[0,4]
      results[games[i]].home_scores = scores[4,8]
    end
 
    total_array.each_slice(2).with_index do |totals, i|
      results[games[i]].totals = totals
    end
 
    results
  end
 
  def get_status html
    results = {}
    game_type = {inprogress: "in-progress", complete: "complete", pregame: "pre-game", cancelled: "cancelled", scheduled: "scheduled"}
 
    game_type.each_pair do |game_type, game_type_css|
      results[game_type] ||= []
      divs = html.xpath(".//div[contains(normalize-space(@class),'holder-#{game_type_css}')]")
      scores = divs.each do |node|
        game_id = node.attribute("id").value.gsub(/[^\d]*/, "")
        results[game_type] << game_id
        results[game_id] = game_type
      end
    end
 
    results
  end
 
  def get_results 
    doc = parse_url BASE_URL + SPORT
    doc_totals = parse_url BASE_URL + SPORT + "totals"
    #doc = parse_test_data
    #doc_totals = parse_test_data
    status = get_status doc
 
    start_dates = doc.xpath('/html/head/meta[@itemprop="startdate"]/@content').collect { |node| node.value }
    names = doc.xpath('/html/head/meta[@itemprop="name"]/@content').collect { |node| node.value }
    urls = doc.xpath('/html/head/meta[@itemprop="url"]/@content').collect { |node| node.value }
    addresses = doc.xpath('/html/head/meta[@itemprop="address"]/@content').collect { |node| node.value }
    games = doc.xpath('.//*[@itemtype="http://schema.org/SportsEvent"]')
 
    #our final results: key = game_id and the value is an openstruct object that holds all the info 
    results = {}
 
    #get the spread and the initial info for a game
    games.each do |game|
      game_result = OpenStruct.new
 
      game_result.game_id = game.attribute('id').value
      game_result.start_date = game.attribute('rel').value
      game_result.rotation = game.xpath('.//div[@class="el-div eventLine-rotation"]/*[@class="eventLine-book-value"]').collect { |node| node.text.strip }
      game_result.time = game.xpath('.//*[@class="el-div eventLine-time"]').collect { |node| node.text.strip }
      game_result.team_id = game.xpath('.//*[@class="team-name"]/@rel').collect { |node| node.text.strip }
      game_result.teams = game.xpath('.//*[@class="el-div eventLine-team"]/*[@class="eventLine-value"]').collect { |node| node.text.strip }
      game_result.tv = game.xpath('.//*[@class="el-div eventLine-tvStation"]/*[@class="eventLine-book-value"]').collect { |node| node.text.strip }
      game_result.spread_consensus = game.xpath('.//*[@class="el-div eventLine-consensus"]/text()').collect { |n| n.content }
      game_result.spread_opener = game.xpath('.//*[@class="el-div eventLine-opener"]/*[@class="eventLine-book-value"]').collect { |node| node.text.strip }
      books = game.xpath('.//*[@class="el-div eventLine-book"]')
 
      game_result.spread_opener = collect_lines(game_result.spread_opener)
 
      game_result.status = status[game_result.game_id] if status.has_key? game_result.game_id
 
      game_result.spread = OpenStruct.new
      books.each do |book|
        live_lines = book.xpath('.//text()')
 
        this_line = collect_lines(live_lines)
        game_result.spread[book['rel']] = this_line if this_line.count > 0
      end
 
      results[game_result.game_id] = game_result
    end
 
 
    #current score struct that holds the quarterly scores and the current total
    current_scores = get_scores(doc)
 
    # Do the totals and associate it with an existing game/timeslot. 
    games = doc_totals.xpath('.//*[@itemtype="http://schema.org/SportsEvent"]')
 
    games.each do |game|
      game_id = game.attribute('id').value
      results[game_id].total_consensus = game.xpath('.//*[@class="el-div eventLine-consensus"]/text()').collect { |n| n.content }
      results[game_id].total_opener = collect_lines game.xpath('.//*[@class="el-div eventLine-opener"]/*[@class="eventLine-book-value"]').collect { |node| node.text.strip }
 
      results[game_id].scores = current_scores[game_id] if current_scores.has_key?(game_id) && results.has_key?(game_id)
 
      books = game.xpath('.//*[@class="el-div eventLine-book"]')
      results[game_id].totals = OpenStruct.new
      books.each do |book|
        live_lines = book.xpath('.//text()')
 
        this_line = collect_lines(live_lines)
        results[game_id].totals[book['rel']] = this_line if this_line.count > 0
      end
    end
    results
  end 
end
 
def index
sc = SportsScraper.new
 
@games = sc.get_results

end
end
