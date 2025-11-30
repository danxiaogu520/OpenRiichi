using Gee;

/**
 * 集合向听与进张的牌效率计算器
 */
public class TileCalculator
{
    public const int AGARI_STATE = -1;

    /**
     * 进张结果信息
     */
    public class UkeireInfo
    {
        public int tile_type_index;           // 牌种索引 (0-33)
        public int remaining_count;           // 剩余可摸张数
        public int shanten_after;             // 摸到此牌后的向听数
        public int narrow_ukeire_after;       // 摸到此牌后的狭义进张数

        public UkeireInfo(int tile_type_index, int remaining_count, int shanten_after, int narrow_ukeire_after)
        {
            this.tile_type_index = tile_type_index;
            this.remaining_count = remaining_count;
            this.shanten_after = shanten_after;
            this.narrow_ukeire_after = narrow_ukeire_after;
        }
    }

    /**
     * 统一的进张结果类
     * 根据手牌数量，返回不同的信息：
     * - 13张牌：返回能让向听数前进的牌种类（ukeire_tiles）
     * - 14张牌：返回推荐打牌顺序（discard_options）
     */
    public class UkeireResult
    {
        // 当前向听数
        public int current_shanten;
        
        // 13张牌时使用：能让向听数前进的牌种类列表
        public ArrayList<UkeireInfo> ukeire_tiles;
        
        // 14张牌时使用：推荐打牌选项（已排序）
        public ArrayList<DiscardOption> discard_options;

        public UkeireResult()
        {
            current_shanten = 999;
            ukeire_tiles = new ArrayList<UkeireInfo>();
            discard_options = new ArrayList<DiscardOption>();
        }
    }

    /**
     * 打牌选项信息
     */
    public class DiscardOption
    {
        public Tile tile;                      // 要打出的牌
        public int shanten_after;              // 打出后的向听数
        public int narrow_ukeire_count;        // 打出后的狭义进张数（张数）
        public int narrow_ukeire_types;        // 打出后的狭义进张种类数
        public ArrayList<UkeireInfo> ukeire_details;  // 详细进张信息

        public DiscardOption(Tile tile)
        {
            this.tile = tile;
            this.shanten_after = 999;
            this.narrow_ukeire_count = 0;
            this.narrow_ukeire_types = 0;
            this.ukeire_details = new ArrayList<UkeireInfo>();
        }
    }

    private int[] tiles;
    private int number_melds;
    private int number_tatsu;
    private int number_pairs;
    private int number_jidahai;
    private int number_characters;
    private int number_isolated_tiles;
    private int min_shanten;

    public TileCalculator()
    {
        tiles = new int[34];
    }

    /**
     * Convert ArrayList<Tile> to 34-tile format
     * Format: 0-8=MAN1-9, 9-17=PIN1-9, 18-26=SOU1-9, 27-33=TON,NAN,SHAA,PEI,HAKU,HATSU,CHUN
     */
    private int[] convert_to_34_array(ArrayList<Tile> hand)
    {
        int[] tiles_34 = new int[34];

        foreach (Tile tile in hand)
        {
            int index = TileRules.tile_type_to_34_index(tile.tile_type);
            if (index >= 0 && index < 34)
                tiles_34[index]++;
        }

        return tiles_34;
    }

    /**
     * Return the minimum shanten for provided hand
     */
    public int calculate_shanten(ArrayList<Tile> hand, ArrayList<RoundStateCall>? calls = null,
                                  bool use_chiitoitsu = true, bool use_kokushi = true)
    {
        // Convert calls to meld count
        int melds_from_calls = 0;
        if (calls != null)
            melds_from_calls = calls.size;

        // Create combined tiles array
        ArrayList<Tile> all_tiles = new ArrayList<Tile>();
        all_tiles.add_all(hand);

        int[] tiles_34 = convert_to_34_array(all_tiles);

        ArrayList<int> shanten_results = new ArrayList<int>();
        shanten_results.add(calculate_shanten_for_regular_hand(tiles_34, melds_from_calls));

        if (use_chiitoitsu && melds_from_calls == 0)
            shanten_results.add(calculate_shanten_for_chiitoitsu_hand(tiles_34));

        if (use_kokushi && melds_from_calls == 0)
            shanten_results.add(calculate_shanten_for_kokushi_hand(tiles_34));

        int min = 999;
        foreach (int result in shanten_results)
        {
            if (result < min)
                min = result;
        }

        return min;
    }

    /**
     * Calculate the number of shanten for chiitoitsu hand
     */
    public int calculate_shanten_for_chiitoitsu_hand(int[] tiles_34)
    {
        int pairs = 0;
        int kinds = 0;

        for (int i = 0; i < 34; i++)
        {
            if (tiles_34[i] >= 2)
                pairs++;
            if (tiles_34[i] >= 1)
                kinds++;
        }

        if (pairs == 7)
            return AGARI_STATE;

        return 6 - pairs + (kinds < 7 ? 7 - kinds : 0);
    }

    /**
     * Calculate the number of shanten for kokushi musou hand
     */
    public int calculate_shanten_for_kokushi_hand(int[] tiles_34)
    {
        // Terminal and honor indices
        int[] indices = {0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33};

        int completed_terminals = 0;
        int terminals = 0;

        foreach (int i in indices)
        {
            if (tiles_34[i] >= 2)
                completed_terminals++;
            if (tiles_34[i] != 0)
                terminals++;
        }

        return 13 - terminals - (completed_terminals > 0 ? 1 : 0);
    }

    /**
     * Calculate the number of shanten for regular hand
     */
    public int calculate_shanten_for_regular_hand(int[] tiles_34, int melds_from_calls = 0)
    {
        // Copy tiles array
        tiles = new int[34];
        for (int i = 0; i < 34; i++)
            tiles[i] = tiles_34[i];

        init_counters();

        int count_of_tiles = 0;
        for (int i = 0; i < 34; i++)
            count_of_tiles += tiles[i];

        remove_character_tiles(count_of_tiles);

        int init_mentsu = melds_from_calls + (14 - count_of_tiles) / 3;
        scan(init_mentsu);

        return min_shanten;
    }

    private void init_counters()
    {
        number_melds = 0;
        number_tatsu = 0;
        number_pairs = 0;
        number_jidahai = 0;
        number_characters = 0;
        number_isolated_tiles = 0;
        min_shanten = 8;
    }

    private void scan(int init_mentsu)
    {
        for (int i = 0; i < 27; i++)
        {
            if (tiles[i] == 4)
                number_characters |= 1 << i;
        }
        number_melds += init_mentsu;
        run(0);
    }

    private void run(int depth)
    {
        if (min_shanten == AGARI_STATE)
            return;

        while (depth < 27 && tiles[depth] == 0)
            depth++;

        if (depth >= 27)
        {
            update_result();
            return;
        }

        int i = depth % 9;

        if (tiles[depth] == 4)
        {
            increase_set(depth);
            if (i < 7 && tiles[depth + 2] > 0)
            {
                if (tiles[depth + 1] > 0)
                {
                    increase_syuntsu(depth);
                    run(depth + 1);
                    decrease_syuntsu(depth);
                }
                increase_tatsu_second(depth);
                run(depth + 1);
                decrease_tatsu_second(depth);
            }

            if (i < 8 && tiles[depth + 1] > 0)
            {
                increase_tatsu_first(depth);
                run(depth + 1);
                decrease_tatsu_first(depth);
            }

            increase_isolated_tile(depth);
            run(depth + 1);
            decrease_isolated_tile(depth);
            decrease_set(depth);
            increase_pair(depth);

            if (i < 7 && tiles[depth + 2] > 0)
            {
                if (tiles[depth + 1] > 0)
                {
                    increase_syuntsu(depth);
                    run(depth);
                    decrease_syuntsu(depth);
                }
                increase_tatsu_second(depth);
                run(depth + 1);
                decrease_tatsu_second(depth);
            }

            if (i < 8 && tiles[depth + 1] > 0)
            {
                increase_tatsu_first(depth);
                run(depth + 1);
                decrease_tatsu_first(depth);
            }

            decrease_pair(depth);
        }

        if (tiles[depth] == 3)
        {
            increase_set(depth);
            run(depth + 1);
            decrease_set(depth);
            increase_pair(depth);

            if (i < 7 && tiles[depth + 1] > 0 && tiles[depth + 2] > 0)
            {
                increase_syuntsu(depth);
                run(depth + 1);
                decrease_syuntsu(depth);
            }
            else
            {
                if (i < 7 && tiles[depth + 2] > 0)
                {
                    increase_tatsu_second(depth);
                    run(depth + 1);
                    decrease_tatsu_second(depth);
                }

                if (i < 8 && tiles[depth + 1] > 0)
                {
                    increase_tatsu_first(depth);
                    run(depth + 1);
                    decrease_tatsu_first(depth);
                }
            }

            decrease_pair(depth);

            if (i < 7 && tiles[depth + 2] >= 2 && tiles[depth + 1] >= 2)
            {
                increase_syuntsu(depth);
                increase_syuntsu(depth);
                run(depth);
                decrease_syuntsu(depth);
                decrease_syuntsu(depth);
            }
        }

        if (tiles[depth] == 2)
        {
            increase_pair(depth);
            run(depth + 1);
            decrease_pair(depth);

            if (i < 7 && tiles[depth + 2] > 0 && tiles[depth + 1] > 0)
            {
                increase_syuntsu(depth);
                run(depth);
                decrease_syuntsu(depth);
            }
        }

        if (tiles[depth] == 1)
        {
            if (i < 6 && tiles[depth + 1] == 1 && tiles[depth + 2] > 0 && tiles[depth + 3] != 4)
            {
                increase_syuntsu(depth);
                run(depth + 2);
                decrease_syuntsu(depth);
            }
            else
            {
                increase_isolated_tile(depth);
                run(depth + 1);
                decrease_isolated_tile(depth);

                if (i < 7 && tiles[depth + 2] > 0)
                {
                    if (tiles[depth + 1] > 0)
                    {
                        increase_syuntsu(depth);
                        run(depth + 1);
                        decrease_syuntsu(depth);
                    }
                    increase_tatsu_second(depth);
                    run(depth + 1);
                    decrease_tatsu_second(depth);
                }

                if (i < 8 && tiles[depth + 1] > 0)
                {
                    increase_tatsu_first(depth);
                    run(depth + 1);
                    decrease_tatsu_first(depth);
                }
            }
        }
    }

    private void update_result()
    {
        int ret_shanten = 8 - number_melds * 2 - number_tatsu - number_pairs;
        int n_mentsu_kouho = number_melds + number_tatsu;

        if (number_pairs > 0)
            n_mentsu_kouho += number_pairs - 1;
        else if (number_characters > 0 && number_isolated_tiles > 0)
        {
            if ((number_characters | number_isolated_tiles) == number_characters)
                ret_shanten++;
        }

        if (n_mentsu_kouho > 4)
            ret_shanten += n_mentsu_kouho - 4;

        if (ret_shanten != AGARI_STATE && ret_shanten < number_jidahai)
            ret_shanten = number_jidahai;

        if (ret_shanten < min_shanten)
            min_shanten = ret_shanten;
    }

    private void increase_set(int k)
    {
        tiles[k] -= 3;
        number_melds++;
    }

    private void decrease_set(int k)
    {
        tiles[k] += 3;
        number_melds--;
    }

    private void increase_pair(int k)
    {
        tiles[k] -= 2;
        number_pairs++;
    }

    private void decrease_pair(int k)
    {
        tiles[k] += 2;
        number_pairs--;
    }

    private void increase_syuntsu(int k)
    {
        tiles[k]--;
        tiles[k + 1]--;
        tiles[k + 2]--;
        number_melds++;
    }

    private void decrease_syuntsu(int k)
    {
        tiles[k]++;
        tiles[k + 1]++;
        tiles[k + 2]++;
        number_melds--;
    }

    private void increase_tatsu_first(int k)
    {
        tiles[k]--;
        tiles[k + 1]--;
        number_tatsu++;
    }

    private void decrease_tatsu_first(int k)
    {
        tiles[k]++;
        tiles[k + 1]++;
        number_tatsu--;
    }

    private void increase_tatsu_second(int k)
    {
        tiles[k]--;
        tiles[k + 2]--;
        number_tatsu++;
    }

    private void decrease_tatsu_second(int k)
    {
        tiles[k]++;
        tiles[k + 2]++;
        number_tatsu--;
    }

    private void increase_isolated_tile(int k)
    {
        tiles[k]--;
        number_isolated_tiles |= 1 << k;
    }

    private void decrease_isolated_tile(int k)
    {
        tiles[k]++;
        number_isolated_tiles &= ~(1 << k);
    }

    private void remove_character_tiles(int nc)
    {
        int number = 0;
        int isolated = 0;

        for (int i = 27; i < 34; i++)
        {
            if (tiles[i] == 4)
            {
                number_melds++;
                number_jidahai++;
                number |= 1 << (i - 27);
                isolated |= 1 << (i - 27);
            }

            if (tiles[i] == 3)
                number_melds++;

            if (tiles[i] == 2)
                number_pairs++;

            if (tiles[i] == 1)
                isolated |= 1 << (i - 27);
        }

        if (number_jidahai > 0 && (nc % 3) == 2)
            number_jidahai--;

        if (isolated > 0)
        {
            number_isolated_tiles |= 1 << 27;
            if ((number | isolated) == number)
                number_characters |= 1 << 27;
        }
    }

    /**
     * 统一的狭义进张计算接口
     * 
     * @param hand 手牌
     * @param calls 副露
     * @param round_state 游戏状态（可选，用于计算可见牌）
     * @return UkeireResult
     * 
     * 行为：
     * - 若手牌+副露=13张：返回所有能让向听数前进的牌种类（ukeire_tiles）
     * - 若手牌+副露=14张：返回手牌的排序副本（discard_options），按打出后向听数排序
     */
    public UkeireResult calculate_narrow_ukeire(ArrayList<Tile> hand,
                                                 ArrayList<RoundStateCall>? calls,
                                                 RoundState? round_state = null)
    {
        UkeireResult result = new UkeireResult();
        
        // 计算总牌数
        int total_tiles = hand.size;
        if (calls != null)
            total_tiles += calls.size * 3;  // 每个副露算3张牌
        
        // 计算当前向听数
        result.current_shanten = calculate_shanten(hand, calls);
        
        // 如果已经和了，没有进张
        if (result.current_shanten == AGARI_STATE)
            return result;
        
        if (total_tiles == 13)
        {
            // 13张牌：返回所有能让向听数前进的牌种类
            result.ukeire_tiles = calculate_13_tiles_narrow_ukeire(hand, calls, round_state, result.current_shanten);
        }
        else if (total_tiles == 14)
        {
            // 14张牌：返回打牌选项，按向听数排序
            result.discard_options = calculate_14_tiles_narrow_discard_options(hand, calls, round_state);
        }
        
        return result;
    }

    /**
     * 统一的广义进张计算接口
     * 
     * @param hand 手牌
     * @param calls 副露
     * @param round_state 游戏状态（可选）
     * @return UkeireResult
     * 
     * 行为：
     * - 若手牌+副露=13张：返回所有能让"向听数前进，或狭义进张数更多"的牌种类（ukeire_tiles）
     * - 若手牌+副露=14张：返回手牌的排序副本（discard_options），首先按向听数排序，对于向听数相同的，按狭义进张数排序
     */
    public UkeireResult calculate_wide_ukeire(ArrayList<Tile> hand,
                                               ArrayList<RoundStateCall>? calls,
                                               RoundState? round_state = null)
    {
        UkeireResult result = new UkeireResult();
        
        // 计算总牌数
        int total_tiles = hand.size;
        if (calls != null)
            total_tiles += calls.size * 3;
        
        // 计算当前向听数
        result.current_shanten = calculate_shanten(hand, calls);
        
        // 如果已经和了，没有进张
        if (result.current_shanten == AGARI_STATE)
            return result;
        
        if (total_tiles == 13)
        {
            // 13张牌：返回所有能让向听数前进或狭义进张数更多的牌种类
            result.ukeire_tiles = calculate_13_tiles_wide_ukeire(hand, calls, round_state, result.current_shanten);
        }
        else if (total_tiles == 14)
        {
            // 14张牌：返回打牌选项，按向听数和狭义进张数排序
            result.discard_options = calculate_14_tiles_wide_discard_options(hand, calls, round_state);
        }
        
        return result;
    }

    /**
     * 计算13张牌时的狭义进张（能让向听数前进的牌种类）
     */
    private ArrayList<UkeireInfo> calculate_13_tiles_narrow_ukeire(ArrayList<Tile> hand,
                                                                     ArrayList<RoundStateCall>? calls,
                                                                     RoundState? round_state,
                                                                     int current_shanten)
    {
        ArrayList<UkeireInfo> ukeire_list = new ArrayList<UkeireInfo>();
        
        // 统计可见牌的数量
        int[] visible_count = count_visible_tiles(hand, calls, round_state);
        
        // 遍历所有34种牌型
        for (int tile_idx = 0; tile_idx < 34; tile_idx++)
        {
            // 计算该牌型还剩多少张可摸
            int remaining = 4 - visible_count[tile_idx];
            if (remaining <= 0)
                continue;
            
            // 模拟摸到这张牌
            TileType tile_type = index_to_tile_type(tile_idx);
            ArrayList<Tile> test_hand = new ArrayList<Tile>();
            test_hand.add_all(hand);
            test_hand.add(new Tile(-1, tile_type, false));
            
            // 尝试打出任意一张牌，看是否能使向听数减少
            bool is_narrow_ukeire = false;
            
            foreach (Tile discard in test_hand)
            {
                ArrayList<Tile> after_discard = new ArrayList<Tile>();
                after_discard.add_all(test_hand);
                after_discard.remove(discard);
                
                int new_shanten = calculate_shanten(after_discard, calls);
                
                // 如果向听数减少，这是狭义进张
                if (new_shanten < current_shanten)
                {
                    is_narrow_ukeire = true;
                    break;
                }
            }
            
            if (is_narrow_ukeire)
            {
                ukeire_list.add(new UkeireInfo(tile_idx, remaining, current_shanten - 1, 0));
            }
        }
        
        return ukeire_list;
    }

    /**
     * 计算13张牌时的广义进张（能让向听数前进或狭义进张数更多的牌种类）
     */
    private ArrayList<UkeireInfo> calculate_13_tiles_wide_ukeire(ArrayList<Tile> hand,
                                                                   ArrayList<RoundStateCall>? calls,
                                                                   RoundState? round_state,
                                                                   int current_shanten)
    {
        ArrayList<UkeireInfo> ukeire_list = new ArrayList<UkeireInfo>();
        
        // 计算当前的狭义进张数
        ArrayList<UkeireInfo> current_narrow = calculate_13_tiles_narrow_ukeire(hand, calls, round_state, current_shanten);
        int current_narrow_count = 0;
        foreach (UkeireInfo info in current_narrow)
            current_narrow_count += info.remaining_count;
        
        // 统计可见牌的数量
        int[] visible_count = count_visible_tiles(hand, calls, round_state);
        
        // 遍历所有34种牌型
        for (int tile_idx = 0; tile_idx < 34; tile_idx++)
        {
            // 计算该牌型还剩多少张可摸
            int remaining = 4 - visible_count[tile_idx];
            if (remaining <= 0)
                continue;
            
            // 模拟摸到这张牌
            TileType tile_type = index_to_tile_type(tile_idx);
            ArrayList<Tile> test_hand = new ArrayList<Tile>();
            test_hand.add_all(hand);
            test_hand.add(new Tile(-1, tile_type, false));
            
            // 尝试打出每一张牌，找到最优结果
            int best_shanten = 999;
            int best_narrow_count = 0;
            
            foreach (Tile discard in test_hand)
            {
                ArrayList<Tile> after_discard = new ArrayList<Tile>();
                after_discard.add_all(test_hand);
                after_discard.remove(discard);
                
                int new_shanten = calculate_shanten(after_discard, calls);
                
                // 计算打出后的狭义进张数
                ArrayList<UkeireInfo> narrow_after = calculate_13_tiles_narrow_ukeire(after_discard, calls, round_state, new_shanten);
                int narrow_count = 0;
                foreach (UkeireInfo info in narrow_after)
                    narrow_count += info.remaining_count;
                
                // 更新最优结果
                if (new_shanten < best_shanten || 
                    (new_shanten == best_shanten && narrow_count > best_narrow_count))
                {
                    best_shanten = new_shanten;
                    best_narrow_count = narrow_count;
                }
            }
            
            // 判断是否是广义进张
            bool is_wide_ukeire = false;
            if (best_shanten < current_shanten)
            {
                // 向听数前进
                is_wide_ukeire = true;
            }
            else if (best_shanten == current_shanten && best_narrow_count > current_narrow_count)
            {
                // 向听数不变，但狭义进张数更多
                is_wide_ukeire = true;
            }
            
            if (is_wide_ukeire)
            {
                ukeire_list.add(new UkeireInfo(tile_idx, remaining, best_shanten, best_narrow_count));
            }
        }
        
        return ukeire_list;
    }

    /**
     * 计算14张牌时的狭义打牌选项（按向听数排序）
     */
    private ArrayList<DiscardOption> calculate_14_tiles_narrow_discard_options(ArrayList<Tile> hand,
                                                                                 ArrayList<RoundStateCall>? calls,
                                                                                 RoundState? round_state)
    {
        ArrayList<DiscardOption> options = new ArrayList<DiscardOption>();
        ArrayList<Tile> tried_types = new ArrayList<Tile>();
        
        foreach (Tile discard_tile in hand)
        {
            // 避免重复计算相同牌型
            bool already_tried = false;
            foreach (Tile tried in tried_types)
            {
                if (tried.tile_type == discard_tile.tile_type)
                {
                    already_tried = true;
                    break;
                }
            }
            if (already_tried)
                continue;
            
            tried_types.add(discard_tile);
            
            // 打出这张牌后的手牌
            ArrayList<Tile> after_discard = new ArrayList<Tile>();
            after_discard.add_all(hand);
            after_discard.remove(discard_tile);
            
            // 创建打牌选项
            DiscardOption option = new DiscardOption(discard_tile);
            option.shanten_after = calculate_shanten(after_discard, calls);
            
            // 计算打出后的狭义进张
            if (option.shanten_after != AGARI_STATE)
            {
                option.ukeire_details = calculate_13_tiles_narrow_ukeire(after_discard, calls, round_state, option.shanten_after);
                
                foreach (UkeireInfo info in option.ukeire_details)
                {
                    option.narrow_ukeire_count += info.remaining_count;
                    option.narrow_ukeire_types++;
                }
            }
            
            options.add(option);
        }
        
        // 按向听数排序（向听数小的优先）
        options.sort((a, b) => {
            return a.shanten_after - b.shanten_after;
        });
        
        return options;
    }

    /**
     * 计算14张牌时的广义打牌选项（按向听数和狭义进张数排序）
     */
    private ArrayList<DiscardOption> calculate_14_tiles_wide_discard_options(ArrayList<Tile> hand,
                                                                               ArrayList<RoundStateCall>? calls,
                                                                               RoundState? round_state)
    {
        ArrayList<DiscardOption> options = new ArrayList<DiscardOption>();
        ArrayList<Tile> tried_types = new ArrayList<Tile>();
        
        foreach (Tile discard_tile in hand)
        {
            // 避免重复计算相同牌型
            bool already_tried = false;
            foreach (Tile tried in tried_types)
            {
                if (tried.tile_type == discard_tile.tile_type)
                {
                    already_tried = true;
                    break;
                }
            }
            if (already_tried)
                continue;
            
            tried_types.add(discard_tile);
            
            // 打出这张牌后的手牌
            ArrayList<Tile> after_discard = new ArrayList<Tile>();
            after_discard.add_all(hand);
            after_discard.remove(discard_tile);
            
            // 创建打牌选项
            DiscardOption option = new DiscardOption(discard_tile);
            option.shanten_after = calculate_shanten(after_discard, calls);
            
            // 计算打出后的狭义进张
            if (option.shanten_after != AGARI_STATE)
            {
                option.ukeire_details = calculate_13_tiles_narrow_ukeire(after_discard, calls, round_state, option.shanten_after);
                
                foreach (UkeireInfo info in option.ukeire_details)
                {
                    option.narrow_ukeire_count += info.remaining_count;
                    option.narrow_ukeire_types++;
                }
            }
            
            options.add(option);
        }
        
        // 按向听数排序，向听数相同时按狭义进张数排序
        options.sort((a, b) => {
            // 首先按向听数排序（向听数小的优先）
            if (a.shanten_after != b.shanten_after)
                return a.shanten_after - b.shanten_after;
            
            // 向听数相同，按进张总数排序（进张多的优先）
            if (a.narrow_ukeire_count != b.narrow_ukeire_count)
                return b.narrow_ukeire_count - a.narrow_ukeire_count;
            
            // 进张总数也相同，按进张种类排序（种类多的优先）
            return b.narrow_ukeire_types - a.narrow_ukeire_types;
        });
        
        return options;
    }

    /**
     * 统计可见牌的数量（包括手牌、副露、弃牌、宝牌指示牌等）
     */
    private int[] count_visible_tiles(ArrayList<Tile> hand,
                                      ArrayList<Tile>? calls,
                                      RoundState? round_state)
    {
        int[] count = new int[34];

        // 始终包含自己的手牌和副露
        add_tiles(count, hand);

        if (round_state == null && calls != null)
            foreach (RoundStateCall call in calls)
                add_tiles(count, call.tiles);

        if (round_state != null)
        {
            // 所有玩家的弃牌与副露
            for (int i = 0; i < 4; i++)
            {
                RoundStatePlayer player = round_state.get_player(i);
                add_tiles(count, player.pond);

                foreach (RoundStateCall call in player.calls)
                    add_tiles(count, call.tiles);
            }

            // 表宝牌指示牌
            add_tiles(count, round_state.dora);
        }

        return count;
    }

    private void add_tiles(int[] count, ArrayList<Tile> tiles_list)
    {
        foreach (Tile tile in tiles_list)
        {
            int idx = tile_type_to_34_index(tile.tile_type);
            if (idx >= 0 && idx < 34)
                count[idx]++;
        }
    }

    private int tile_type_to_34_index(TileType type)
    {
        if (type >= TileType.MAN1 && type <= TileType.MAN9)
            return (int)type - (int)TileType.MAN1;
        else if (type >= TileType.PIN1 && type <= TileType.PIN9)
            return (int)type - (int)TileType.PIN1 + 9;
        else if (type >= TileType.SOU1 && type <= TileType.SOU9)
            return (int)type - (int)TileType.SOU1 + 18;
        else if (type >= TileType.TON && type <= TileType.CHUN)
            return (int)type - (int)TileType.TON + 27;

        return -1;
    }

    private TileType index_to_tile_type(int index)
    {
        if (index >= 0 && index <= 8)
            return (TileType)((int)TileType.MAN1 + index);
        else if (index >= 9 && index <= 17)
            return (TileType)((int)TileType.PIN1 + index - 9);
        else if (index >= 18 && index <= 26)
            return (TileType)((int)TileType.SOU1 + index - 18);
        else if (index >= 27 && index <= 33)
            return (TileType)((int)TileType.TON + index - 27);

        return TileType.BLANK;
    }
}