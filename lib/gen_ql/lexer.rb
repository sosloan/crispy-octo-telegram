# frozen_string_literal: true

module GenQL
  # A single token emitted by the Lexer.
  Token = Struct.new(:type, :value)

  # Tokenises a GenQL query string into a flat array of Tokens.
  #
  # Token types:
  #   :QUERY :MUTATION :SUBSCRIPTION  – operation keywords
  #   :NAME                           – identifiers
  #   :STRING :INT :FLOAT             – literal values
  #   :TRUE :FALSE :NULL              – boolean / null literals
  #   :LBRACE :RBRACE                 – { }
  #   :LPAREN :RPAREN                 – ( )
  #   :COLON :COMMA                   – : ,
  #   :EOF
  class Lexer
    KEYWORDS = {
      'query' => :QUERY,
      'mutation' => :MUTATION,
      'subscription' => :SUBSCRIPTION,
      'true' => :TRUE,
      'false' => :FALSE,
      'null' => :NULL
    }.freeze

    def initialize(source)
      @source = source
      @pos    = 0
      @tokens = []
    end

    def tokenize
      until @pos >= @source.length
        skip_ignored
        break if @pos >= @source.length

        char = @source[@pos]
        case char
        when '{'  then emit(:LBRACE, char)
        when '}'  then emit(:RBRACE, char)
        when '('  then emit(:LPAREN, char)
        when ')'  then emit(:RPAREN, char)
        when ':'  then emit(:COLON, char)
        when ','  then emit(:COMMA, char)
        when '"'  then @tokens << scan_string
        when /[0-9-]/ then @tokens << scan_number
        when /[a-zA-Z_]/ then @tokens << scan_name
        else
          raise LexError, "Unexpected character '#{char}' at position #{@pos}"
        end
      end
      @tokens << Token.new(:EOF, nil)
      @tokens
    end

    private

    def emit(type, char)
      @tokens << Token.new(type, char)
      @pos += 1
    end

    def skip_ignored
      while @pos < @source.length
        c = @source[@pos]
        if c =~ /[\s,]/
          @pos += 1
        elsif c == '#'
          @pos += 1 while @pos < @source.length && @source[@pos] != "\n"
        else
          break
        end
      end
    end

    # rubocop:disable Metrics/MethodLength
    def scan_string
      @pos += 1 # skip opening quote
      result = +''
      while @pos < @source.length && @source[@pos] != '"'
        if @source[@pos] == '\\'
          @pos += 1
          result << case @source[@pos]
                    when 'n' then "\n"
                    when 't' then "\t"
                    when 'r' then "\r"
                    when '"' then '"'
                    when '\\' then '\\'
                    else @source[@pos]
                    end
        else
          result << @source[@pos]
        end
        @pos += 1
      end
      raise LexError, 'Unterminated string literal' if @pos >= @source.length

      @pos += 1 # skip closing quote
      Token.new(:STRING, result)
    end
    # rubocop:enable Metrics/MethodLength

    # rubocop:disable Metrics/PerceivedComplexity
    def scan_number
      start = @pos
      @pos += 1 if @source[@pos] == '-'
      @pos += 1 while @pos < @source.length && @source[@pos] =~ /[0-9]/
      if @pos < @source.length && @source[@pos] == '.'
        @pos += 1
        @pos += 1 while @pos < @source.length && @source[@pos] =~ /[0-9]/
        Token.new(:FLOAT, @source[start...@pos].to_f)
      else
        Token.new(:INT, @source[start...@pos].to_i)
      end
    end
    # rubocop:enable Metrics/PerceivedComplexity

    def scan_name
      start = @pos
      @pos += 1 while @pos < @source.length && @source[@pos] =~ /[a-zA-Z0-9_]/
      value = @source[start...@pos]
      Token.new(KEYWORDS.fetch(value, :NAME), value)
    end
  end

  class LexError < StandardError
  end
end
