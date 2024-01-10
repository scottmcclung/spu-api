require "../src/spu-api"

  acct = Spu::Account.new("1201 2nd Ave")
  p acct.next_collection_day
  p acct.collection_schedule
