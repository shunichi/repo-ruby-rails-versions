require 'json'
require 'csv'

json = JSON.parse(IO.read(ARGV[0]))

def to_csv(json)
  CSV.generate do |csv|
    json.each do |r|
      if s = r['specs'].find { |s| s['name'] == 'rails'}
        rails_version = s['version']
      end
      csv << [
        r['full_name'],
        r['ruby_version'].to_s,
        rails_version,
      ]
    end
  end
end

puts to_csv(json)
