import subprocess

# Set the command
command = "cd /Users/lancy/.jenkins/workspace/TryOutProject/; git log --pretty=format:%B -10"

# Setup the module object
proc = subprocess.Popen(command,
                    shell=True,
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE)

# Communicate the command
stdout_value,stderr_value = proc.communicate()
str_list = filter(None, stdout_value.decode("ascii").splitlines())
commitMessages = "<br>".join(str_list)
data = '{"release_notes" : \"'+commitMessages+'\"}'
print(data)

