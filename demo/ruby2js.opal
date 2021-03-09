require 'native'
require 'ruby2js/demo'
require 'patch.opal'
require 'filters.opal'

# support environment specific default options
module Ruby2JS
  @default_options = {}

  def self.default_options
    @default_options
  end
end

%x{ 
  if (typeof require === 'function' && typeof process === 'object') {
    // load rb2js.config.rb for default options
    try {
      const child_process = require('child_process');
      const fs = require('fs');

      const config_file = `${process.cwd()}/rb2js.config.rb`;

      if (fs.existsSync(config_file)) {
        let options = JSON.parse(child_process.execSync(`ruby -e "${`
          require '${config_file}'
          require 'json'

          puts({ filters: Ruby2JS::Filter::DEFAULTS.map {|mod|
            method = mod.instance_method(mod.instance_methods.first)
            File.basename(method.source_location.first, '.rb')
          }, **Ruby2JS::Loader.options}.to_json)
        `}"`, {encoding: 'utf8'}));

        Opal.Ruby2JS.default_options['$merge!'](Opal.hash(options))
      }
    } catch(error) {
      // error already appears on STDERR, no further recovery is required
    }

    // parse RUBY2JS_OPTIONS environment variable for default options
    try {
      let options = process.env['RUBY2JS_OPTIONS'];
      if (options) {
        Opal.Ruby2JS.default_options['$merge!'](Opal.hash(JSON.parse(options)))
      }
    } catch(error) {
      console.error(`Error parsing RUBY2JS_OPTIONS: ${error.message}`) 
    }
  }
}

# fixup options:
#   * map filter names to filter modules
#   * parse autoimports, defs
def Ruby2JS.options(hash)
  hash = default_options.merge(`Opal.hash(hash || {})`)

  hash[:filters] ||= []
  hash[:filters] = hash[:filters].split(/,\s*/) if hash[:filters].is_a? String
`require('fs').writeFileSync("/home/rubys/tmp/filters", JSON.stringify(hash.$$smap))`
  hash[:filters] = hash[:filters].map {|name| Filters[name]}
  hash[:filters].compact!

  if hash[:autoimports].is_a? String
    hash[:autoimports] = Ruby2JS::Demo.parse_autoimports(hash[:autoimports])
  end

  if hash[:defs].is_a? String
    hash[:defs] = Ruby2JS::Demo.parse_defs(hash[:defs])
  end

  hash
end

# Make Ruby2JS::SyntaxError a JavaScript SyntaxError
class Ruby2JS::SyntaxError
  def self.new(message, diagnostic=nil)
    error = `new SyntaxError(message)`
    if diagnostic
      lines = diagnostic.render.map {|line| line.sub(/^\(string\):/, '')}
      lines[-1] += '^' if diagnostic.location.size == 0
      `error.diagnostic = lines.join("\n")`
    end
    return error
  end
end

# Make convert, parse, and AST.Node, nil available to JavaScript
`var Ruby2JS = {
  convert(string, options) {
    return Opal.Ruby2JS.$convert(string, Opal.Ruby2JS.$options(options))
  },

  parse(string, options) {
    return Opal.Ruby2JS.$parse(string, Opal.Ruby2JS.$options(options))
  },

  AST: {Node: Opal.Parser.AST.Node},

  nil: Opal.nil
}`

# Define a getter for sourcemap
`Object.defineProperty(Opal.Ruby2JS.Serializer.$$prototype, "sourcemap",
  {get() { return this.$sourcemap().$$smap }})`

# advertise that the function is available
if `typeof module !== 'undefined' && module.parent`
  `module.exports = Ruby2JS`
else
  $$.Ruby2JS = `Ruby2JS`
  if $$.document and $$.document[:body]
    $$.document[:body].dispatchEvent(`new CustomEvent('Ruby2JS-ready')`)
  end
end
