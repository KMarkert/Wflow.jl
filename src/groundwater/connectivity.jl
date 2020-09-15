"""
Stores connection data between cells. Connections are stored in a compressed
sparse column (CSC) adjacency matrix: only non-zero values are stored.
Primarily, this consist of two vectors:
* the row value vector holds the cell indices of neighbors
* the column pointers marks the start and end index of the row value vector

This matrix is square: n = m = ncell. nconnection is equal to nnz (the number of
non-zero values).

* ncell: the number of (active) cells in the simulation
* nconnection: the number of connections between cells
* external: maps the internal cell numbering -- a linear index -- to the
  external (user-supplied) numbering (rows and columns in case of structured
  input) 
* internal: maps the external cell numbering (row, column) to the internal
  numbering (a linear index)
* length1: for every connection, the length in the first cell, size nconnection
* length2: for every connection, the length in the second cell, size nconnection
* width: width for every connection, (approx.) perpendicular to length1 and
  length2, size nconnection
* colptr: CSC column pointer (size ncell + 1)
* rowval: CSC row value (size nconnection)
"""
struct Connectivity{T}
    ncell::Int
    nconnection::Int
    # Map internal nodes to external id's
    external::Vector{CartesianIndex,2}
    # Map external nodes to internal id's
    internal::Array{Int,2}
    length1::Vector{T}
    length2::Vector{T}
    width::Vector{T}
    colptr::Vector{Int}
    rowval::Vector{Int}
end
# TODO: maybe remove internal and external mappings from this structure?

"""
Returns connections for a single cell, identified by ``id``.
"""
connections(C::Connectivity, id::Int) = C.colptr[id]:(C.colptr[id + 1] - 1)


"""
Assign cell id's to the two dimensional array and 0 to inactive cells.
"""
function create_mapping(domain::Array{Bool,2})
    internal = similar(domain, Int)
    external = similar(domain, CartesianIndex)
    id = 0
    for I in CartesianIndices(domain)
        if domain[I]
            id += 1
            internal[I] = id
            external[id] = I
        else
            internal[I] = 0
        end
    end
    return internal, external[1:id]
end


"""
Compute geometrical properties of connections for structured input.
"""
function connection_geometry(I, J, Δx, Δy)
    if I[1] != J[1]  # connection in x
        length1 = 0.5 * Δx[J[1]]
        length2 = 0.5 * Δx[I[1]]
        width = Δy[I[2]]
    elseif I[2] != J[2]  # connection in y
        length1 = 0.5 * Δy[J[2]]
        length2 = 0.5 * Δy[I[2]]
        width = Δx[I[1]]
    else
        error("Inconsistent index")
    end
    return (length1, length2, width)
end


# Define cartesian indices for neighbors
const LEFT = CartesianIndex(-1, 0)
const RIGHT = CartesianIndex(1, 0)
const BACK = CartesianIndex(0, -1)
const FRONT = CartesianIndex(0, 1)


# Constructor for the Connectivity structure for structured input
function Connectivity(domain::Array{Bool,2}, Δx::Vector{T}, Δy::Vector{T})
    nrow, ncol = size(domain)
    # Create internal <-> external id mappings
    internal, external = create_mapping(domain)

    # Pre-allocate output, allocate for full number of neighbors (4)
    # We'll store only the part we need
    ncell = length(external)
    colptr = Vector{Int}(undef, ncell + 1)
    rowval = Vector{Int}(undef, ncell * 4)
    length1 = similar(rowval, T)
    length2 = similar(rowval, T)
    width = similar(rowval, T)

    i = 1  # column index of sparse matrix
    j = 1  # row index of sparse matrix
    colptr[1] = i
    for I in CartesianIndices(internal)
        row_i = i
        # Strictly increasing numbering for any row
        # (Required by a CSCSparseMatrix)
        for neighbor in (FRONT, LEFT, RIGHT, BACK)
            J = I + neighbor
            if (1 <= J[1] <= ncol) && (1 <= J[2] <= nrow) # Check if it's inbounds
                rowval[i] = internal[J]
                length1[i], length2[i], width[i] = connection_geometry(
                    I, J, Δx, Δy
                )
                i += 1
            end
        end
        j += 1
        colptr[j] = row_i
    end

    nconnection = i - 1
    return Connectivity(
            ncell,
            nconnection,
            external,
            internal,
            length1[1:nconnection],
            length2[1:nconnection],
            width[1:nconnection],
            colptr,
            rowval,
    )
end