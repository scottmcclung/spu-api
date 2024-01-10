# spu-api

TODO: Write a description here

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     spu-api:
       github: scottmcclung/spu-api
   ```

2. Run `shards install`

## Usage

```crystal
require "spu-api"

acct = Spu::Account.new("1201 2nd Ave")
p acct.next_collection_day
p acct.collection_schedule
```

TODO: Write usage instructions here


## Contributing

1. Fork it (<https://github.com/scottmcclung/spu-api/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Scott McClung](https://github.com/scottmcclung) - creator and maintainer
