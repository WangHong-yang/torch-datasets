require 'fn'
require 'fn/seq'
require 'util/arg'
require 'dataset'
local arg = util.arg

local TableDataset = torch.class("dataset.TableDataset")


-- Wraps a table containing a dataset to make it easy to transform the dataset
-- and then sample from.  Each property in the data table must have a tensor or
-- table value, and then each sample will be retrieved by indexing these values
-- and returning a single instance from each one.
--
-- e.g.
--
--   -- a 'dataset' of random samples with random class labels
--   data_table = {
--     data  = torch.Tensor(10, 20, 20),
--     class = torch.randperm(10)
--   }
--   metadata = { name = 'random', classes = {1,2,3,4,5,6,7,8,9,10} }
--   dataset = TableDataset(data_table, metadata)
--
function TableDataset:__init(data_table, global_metadata)

   self.dataset = data_table

   global_metadata = global_metadata or {}

   self._name = global_metadata.name
   self._classes = global_metadata.classes or {}
end


-- Returns the number of samples in the dataset.
function TableDataset:size()
   return self.dataset.data:size(1)
end


-- Returns the dimensions of a single sample as a table.
-- e.g.
--   mnist          => {1, 28, 28}
--   natural images => {3, 64, 64}
function TableDataset:dimensions()
   local dims = self.dataset.data:size():totable()
   table.remove(dims, 1)
   return dims
end


-- Returns the total number of dimensions of a sample.
-- e.g.
--   mnist => 1*28*28 => 784
function TableDataset:n_dimensions()
   return fn.reduce(fn.mul, 1, self:dimensions())
end


-- Returns the classes represented in this dataset (if available).
function TableDataset:classes()
   return self._classes
end


-- Returns the string name of this dataset.
function TableDataset:name()
   return self._name
end


-- Returns the specified sample (a table) by index.
--
--   sample = dataset:sample(100)
function TableDataset:sample(i)
    local sample = {}

    for key, v in pairs(self.dataset) do
        sample[key] = v[i]
    end

    return sample
end


-- Returns an infinite sequence of data samples.  By default they
-- are shuffled samples, but you can turn shuffling off.
--
--   for sample in seq.take(1000, dataset:sampler()) do
--     net:forward(sample.data)
--   end
--
--   -- turn off shuffling
--   sampler = dataset:sampler({shuffled = false})
function TableDataset:sampler(options)
   options = options or {}
   local shuffled = arg.optional(options, 'shuffled', true)
   local indices
   local size = self:size()

   local function make_sampler()
       if shuffled then
           indices = torch.randperm(size)
       else
           indices = seq.range(size)
       end
       return seq.map(fn.partial(self.sample, self), indices)
   end

   return seq.flatten(seq.cycle(seq.repeatedly(make_sampler)))
end


-- Returns the ith mini batch consisting of a table of tensors.
--
--   local batch = dataset:mini_batch(1)
--
--   -- or use directly
--   net:forward(dataset:mini_batch(1).data)
--
--   -- set the batch size using an options table
--   local batch = dataset:mini_batch(1, {size = 100})
--
--   -- or get batch as a sequence of samples, rather than a full tensor
--   for sample in dataset:mini_batch(1, {sequence = true}) do
--     net:forward(sample.data)
--   end
function TableDataset:mini_batch(i, options)
   options = options or {}
   local batch_size   = arg.optional(options, 'size', 10)
   local as_seq = arg.optional(options, 'sequence', false)
   local batch = {}

   if as_seq then
      return seq.map(fn.partial(self.sample, self), seq.range(i, i + batch_size-1))
   else
       for key, v in pairs(self.dataset) do
           batch[key] = v:narrow(1, i, batch_size)
       end

       return batch
   end
end


-- Returns an infinite sequence of mini batches.
--
--   -- default options returns contiguous tensors of batch size 10
--   for batch in dataset:mini_batches() do
--      net:forward(batch.data)
--   end
--
--   -- It's also possible to set the size, and/or get the batch as a sequence of
--   -- individual samples.
--   for batch in (seq.take(N_BATCHES, dataset:mini_batches({size = 100, sequence=true})) do
--     for sample in batch do
--       net:forward(sample.data)
--     end
--   end
--
function TableDataset:mini_batches(options)
   options = options or {}
   local shuffled = arg.optional(options, 'shuffled', true)
   local mb_size = arg.optional(options, 'size', 10)
   local indices
   local size = self:size()

   if shuffled then
      indices = torch.randperm(size / mb_size)
   else
      indices = seq.range(size / mb_size)
   end

   return seq.map(function(i)
                     return self:mini_batch((i-1) * mb_size + 1, options)
                  end,
                  indices)
end


-- Returns the sequence of frames corresponding to a specific sample's animation.
--
--   for frame,label in m:animation(1) do
--      local img = frame:unfold(1,28,28)
--      win = image.display({win=win, image=img, zoom=10})
--      util.sleep(1 / 24)
--   end
--
function TableDataset:animation(i)
   local start = ((i-1) * self.frames) + 1
   return self:mini_batch(start, self.frames, {sequence = true})
end


-- Returns a sequence of animations, where each animation is a sequence of
-- samples.
--
--   for anim in m:animations() do
--      for frame,label in anim do
--         local img = frame:unfold(1,28,28)
--         win = image.display({win=win, image=img, zoom=10})
--         util.sleep(1 / 24)
--      end
--   end
--
function TableDataset:animations(options)
   options = options or {}
   local shuffled = arg.optional(options, 'shuffled', true)
   local indices

   if shuffled then
      indices = torch.randperm(self.base_size)
   else
      indices = seq.range(self.base_size)
   end
   return seq.map(function(i)
                     return self:animation(i)
                  end,
                  indices)
end

