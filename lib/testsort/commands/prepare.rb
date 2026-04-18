desc 'all', 'Prepare the repository in a fault-full commit by checking out a previous commit and putting it into the staging area'

option :commit, aliases: '-c', type: :string, desc: 'The commit to checkout', banner: '[commit_hash]'
option :reset, aliases: '-r', type: :string, desc: 'The commit to reset towards', banner: '[commit_hash]'

def prepare
  RepositoryManager::RepositoryPreparation.prepare(options.commit, options.reset, verbose: true, set_state: true)
end
