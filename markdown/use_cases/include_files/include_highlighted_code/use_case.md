        <table>
            <tr>
              <th>Prev</th>
              <td><a href="../include_code_block/use_case.md">Include Code Block</a></td>
            </tr>

            <tr>
              <th>Next</th>
              <td><a href="../include_page_toc/use_case.md">Include Page TOC</a></td>
            </tr>

        </table>

### Include Highlighted Code

Use file inclusion to include text as highlighted code.

#### File to Be Included

Here's a file containing Ruby code to be included:

```hello.rb```:
```markdown
class HelloWorld
   def initialize(name)
      @name = name.capitalize
   end
   def sayHi
      puts "Hello !"
   end
end
```

#### Includer File

Here's a template file that includes it:

```includer.md```:
```markdown
This file includes the code as highlighted code.

@[ruby](hello.rb)

```

The treatment token ```ruby``` specifies that the included text is to be highlighted as Ruby code.

The treatment token can be any Ace mode mentioned in [GitHub Languages](https://github.com/github/linguist/blob/master/lib/linguist/languages.yml).  The file lists about 100 Ace modes, covering just about every language and format.

#### CLI

You can use the command-line interface to perform the inclusion.

##### Command

```sh
markdown_helper include --pristine includer.md included.md
```

(Option ```--pristine``` suppresses comment insertion.)

#### API

You can use the API to perform the inclusion.

##### Ruby Code

```include.rb```:
```ruby
require 'markdown_helper'

# Option :pristine suppresses comment insertion.
markdown_helper = MarkdownHelper.new(:pristine => true)
markdown_helper.include('includer.md', 'included.md')
```

##### Command

```sh
ruby include.rb
```

#### File with Inclusion

Here's the finished file with the included highlighted code:

<pre>
This file includes the code as highlighted code.

```hello.rb```:
```ruby
class HelloWorld
   def initialize(name)
      @name = name.capitalize
   end
   def sayHi
      puts "Hello !"
   end
end
```

</pre>

And here's the finished markdown, as rendered on this page:

---

This file includes the code as highlighted code.

```hello.rb```:
```ruby
class HelloWorld
   def initialize(name)
      @name = name.capitalize
   end
   def sayHi
      puts "Hello !"
   end
end
```


---

        <table>
            <tr>
              <th>Prev</th>
              <td><a href="../include_code_block/use_case.md">Include Code Block</a></td>
            </tr>

            <tr>
              <th>Next</th>
              <td><a href="../include_page_toc/use_case.md">Include Page TOC</a></td>
            </tr>

        </table>
