require "../src/spu-api"

  acct = Spu::Account.new("13747 39th Ave NE")
  p acct.next_collection_day
  p acct.collection_schedule
  p acct.address
