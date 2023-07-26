#=======================================================================================================================
# Create a mesh for the dam break simple test case
#=======================================================================================================================

#-----------------------------------------------------------------------------------------------------------------------
# Parameters
#-----------------------------------------------------------------------------------------------------------------------
# Number of cross-sections
N = 201

#-----------------------------------------------------------------------------------------------------------------------
# Main program
#-----------------------------------------------------------------------------------------------------------------------
mesh_file = open("channel_%i.geo" % N, 'w')
mesh_file.write("# Simple channel mesh\n")
mesh_file.write("%i 1\n" % N)
mesh_file.write("# Cross sections\n")
for i in range(N):
   x = i * (float(25.0) / (N-1))
   y = 0.0
   bathy = 0.0
   nsections = 1
   height = 1000.0
   width = 1.0
   mesh_file.write("%i %.1f %.1f %.2f %i\n" % (i+1, x, y, bathy, nsections))
   mesh_file.write("%.2f %.2f 0.0\n"  % (height, width))
mesh_file.close()