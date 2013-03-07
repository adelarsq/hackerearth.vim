" check for python
if !has('python')
    echoerr "HackerEarth: Plugin needs to be compiled with python support."
    finish
endif

" check for client key
if exists("g:HackerEarthApiClientKey")
    let s:client_key = g:HackerEarthApiClientKey
else
    let errmsg = "You need to set client key in your vimrc file"
    echoerr errmsg
    finish
endif

" Default output buffer
let s:output_buffer = "HackerEarth"

setlocal wildmode=longest

"
" Helper functions
"

" Function that opens or navigates to the scratch buffer.
function! s:OutputBufferOpen(name)
    let scr_bufnum = bufnr(a:name)
    if scr_bufnum == -1
        exe "new " . a:name
    else
        let scr_winnum = bufwinnr(scr_bufnum)
        if scr_winnum != -1
            if winnr() != scr_winnum
                exe scr_winnum . "wincmd w"
            endif
        else
            exe "split +buffer" . scr_bufnum
        endif
    endif
    call s:OutputBuffer()
endfunction

" After opening the scratch buffer, this sets some properties for it.
function! s:OutputBuffer()
    setlocal buftype=nofile
    setlocal bufhidden=hide
    setlocal noswapfile
    setlocal filetype=txt
endfunction

python << ENDPYTHON

import vim, urllib2, os
import json

COMPILE_URL = "http://api.hackerearth.com/code/compile/"
RUN_URL = "http://api.hackerearth.com/code/run/"
CLIENT_SECRET = vim.eval("s:client_key")
OUTPUT_BUFFER = vim.eval("s:output_buffer")
LANGS = {
    'c':'C',
    'cpp':'CPP',
    'clj':'CLOJURE',
    'java':'JAVA',
    'js':'JAVASCRIPT',
    'lhs':'HASKELL',
    'pl':'PERL',
    'php':'PHP',
    'py':'PYTHON',
    'rb':'RUBY',
}

class Api(object):

    def __init__(self, arg):
        self.arg = arg
        
    def call(self):
        try:
            url = self.url()
            post = self.setpostdata()
            response = urllib.urlopen(url, post).read()
            response = json.loads(response)
            response = self.convert(response)
            vimi = VimInterface(response, self.arg.output_file)
            vimi.showoutput()
            vimi.saveoutput()
        except IOError, e:
            print e

    def source(self):
        return open(self.arg.source_file, 'r').read()

    def lang(self, file_extension):
       if(LANGS.has_key(file_extension)):
            return LANGS[file_extension]
       else:
            return file_extension

    def input(self):
        input = open(self.arg.input_file, 'r').read() if(self.hasinput()) else None
        return input
                
    def timelimit(self):
        return self.arg.time_limit

    def memorylimit(self):
        return self.arg.memory_limit
        
    def url(self):
        url = COMPILE_URL if(self.arg.action=="compile") else RUN_URL
        return url
    
    def hasinput(self):
        check = True if(self.arg.input_file is not None) else False
        return check
             
    def hastimelimit(self):
        check = True if(self.arg.time_limit is not None) else False
        return check
        
    def hasmemorylimit(self):
        check = True if(self.arg.memory_limit is not None) else False
        return check

    def setpostdata(self):
        source = self.source()
        lang = self.lang(File.extension(self.arg.source_file))
        
        post_data = {
            'client_secret': CLIENT_SECRET,
            'source': source,
            'lang': lang,
        }

        input = self.input()
        timelimit = self.timelimit()
        memorylimit = self.memorylimit()

        if(self.hasinput()):
            post_data['input'] = input
        if(self.hastimelimit()):
            post_data['time_limit'] = timelimit
        if(self.hasmemorylimit()):
            post_data['memory_limit'] = memorylimit

        post_data = urllib.urlencode(post_data) 
        return post_data

    def convert(self, input):
        if isinstance(input, dict):
            return {self.convert(key): self.convert(value) for key, value in input.iteritems()}
        elif isinstance(input, list):
            return [self.convert(element) for element in input]
        elif isinstance(input, unicode):
            return input.encode('utf-8')
        else:
            return input

class File(object):
    
    @staticmethod
    def abspath(file_path):
        if(file_path is not None):
            path = os.path
            file_path = path.expanduser(file_path)
            if(not(path.isabs(file_path))):
                file_path = path.abspath(file_path)
        return file_path

    @staticmethod
    def extension(file_path):
        if(file_path is not None):
            path = os.path
            filename, fileextension = path.splitext(file_path)
            fileextension = fileextension.replace('.','')
            return fileextension 

class VimInterface(object):
    
    def __init__(self, output=None, output_file=OUTPUT_BUFFER):
        self.output = output
        self.output_file = output_file

    def loadbuffer(self):
        if(self.output_file!=OUTPUT_BUFFER):
            vim.command("new %s" % File.abspath(self.output_file).replace(' ','\ '))
        else:
            vim.command("call s:OutputBufferOpen('%s')" % OUTPUT_BUFFER)
        buff = vim.current.buffer
        del buff[:]
        return buff
     
    def showoutput(self):
        buff = self.loadbuffer()
        output = self.output
        buff[0] = 35*"-"+"HackerEarth"+35*"-"
        buff.append("")
        message = output['message']
        if(message=="OK"):
            buff.append("Web link: %s"%output['web_link'])
            compile_status = "Compile status: %s" % output['compile_status']
            self.appendlines(compile_status, buff)
            
            if(output.has_key('run_status')):
                o = output['run_status']    
                status = o['status']
                buff.append("Run status: %s" % status)
                if(status=='AC'):
                    self.appendlines("Output: %s" % o['output'], buff)
                    buff.append("Time used: %s sec" % o['time_used'])
                    buff.append("Memory used: %s KiB" % o['memory_used'])
                if(status=="CE"):
                    self.appendlines(o['status_detail'], buff)
                if(status=="TLE"):
                    buff.append("Time used: %s sec" % o['time_used'])
                    buff.append("Memory used: %s KiB" % o['memory_used'])
                if(status=="RE"):
                    buff.append("Status detail: %s" % o['status_detail'])
        else:
            buff.append("Message: %s" % message)
            if(output['errors']!=""):
                self.appendlines("Errors: %s" % output['errors'], buff)

    def saveoutput(self):
        if(self.output_file!=OUTPUT_BUFFER):
            vim.command("w")

    def appendlines(self, string, buff):
        lines = string.strip().split('\n')
        for line in lines:
            buff.append(line)

class Argument(object):
    
    def __init__(self, source_file, input_file, output_file, time_limit, memory_limit, Help):
        self.source_file = source_file
        self.input_file = input_file
        self.output_file = output_file
        self.time_limit = time_limit
        self.memory_limit = memory_limit
        self.Help = Help

    @staticmethod
    def defaultargs(cls):
        cls.source_file = vim.eval("expand('%:p')")
        cls.input_file = cls.time_limit = cls.memory_limit = None
        cls.output_file = vim.eval("s:output_buffer")
        cls.Help = False
       
    @classmethod
    def evalargs(cls, args):
        
        Argument.defaultargs(cls)

        if(not args):
            return cls(File.abspath(cls.source_file), File.abspath(cls.input_file), cls.output_file, cls.time_limit, cls.memory_limit, cls.Help)
        # strip extra white spaces
        args = ' '.join(args.split())
        args = args.replace("= ","=")
        args = args.replace(", ",",")
        args = str.split(args, ",")
        for arg in args:
            a = str.split(arg, "=")
            if(a[0]=="-s" and a[1] is not None):
                cls.source_file = a[1]
            elif(a[0]=="-i" and a[1] is not None):
                cls.input_file = a[1]
            elif(a[0]=="-o" and a[1] is not None):
                cls.output_file = a[1]
            elif(a[0]=="-t" and a[1] is not None):
                cls.time_limit = a[1]
            elif(a[0]=="-m" and a[1] is not None):
                cls.memory_limit = a[1]
            else:
                cls.Help = True;
                break;
        return cls(File.abspath(cls.source_file), File.abspath(cls.input_file), cls.output_file, cls.time_limit, cls.memory_limit, cls.Help)

    def printargs(self):
        print "-s=%s, -i=%s, -o=%s, -t=%s, -m=%s" % (self.source_file,self.input_file,self.output_file,self.time_limit,self.memory_limit)

    def setaction(self, action):
        self.action = action

ENDPYTHON

function! s:Hhelp()
python << EOF
help_text = 35*"-"+"Help"+35*"-"+"""

Commands:
To run: :Hrun -s=source.cpp, -i=input.txt, -o=output.txt
To compile: :Hcompile -s=source.cpp, -i=input.txt, -o=output.txt
For help: :Hhelp

Arguments:
-s: source file, optional; default value is currently openend file in vim
-i: input file, optionali; give input to your programme from this file
-o: output file, optional; use this if you want to save the output of your programme
-t: time limit, optional
-m: memory limit, optional

Note*: File paths can be both absolute and relative(relative to system current working directory).
Tip*: To autocomplete file path, use space after '=' and press TAB."""
vimi = VimInterface()
buff = vimi.loadbuffer()
vimi.appendlines(help_text, buff)
EOF
endfunction

function! s:HackerEarth(action, ...)
python << EOF
action = vim.eval("a:action")
argslist = vim.eval("a:000")
args = None if(not argslist) else argslist[0]
arg = Argument.evalargs(args)
arg.setaction(action)
#print arg.printargs()
if(not arg.Help):
    api = Api(arg)
    api.call()
else:
    vim.command("Hhelp")
EOF
endfunction

command! -nargs=? -complete=file Hrun :call <SID>HackerEarth("run", <f-args>)
command! -nargs=? -complete=file Hcompile :call <SID>HackerEarth("compile", <f-args>)
command! -nargs=0 Hhelp :call <SID>Hhelp()

map <C-h>r :Hrun<CR>
map <C-h>c :Hcompile<CR>
map <C-h>h :Hhelp<CR>
